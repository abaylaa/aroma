"""
Aroma Lab - Flask MVP
Run:
    pip install flask
    python app.py
Then open http://127.0.0.1:5000/
"""
import os
import sqlite3
from functools import wraps
from flask import (
    Flask, render_template, request, redirect, url_for,
    session, flash, g, abort
)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DATABASE = os.path.join(BASE_DIR, "aroma_lab_en.db")

app = Flask(__name__)
app.secret_key = "aroma-lab-dev-secret-change-me"

# ---------- DB helpers ----------
def get_db():
    if "db" not in g:
        g.db = sqlite3.connect(DATABASE)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON;")
    return g.db

@app.teardown_appcontext
def close_db(exc):
    db = g.pop("db", None)
    if db is not None:
        db.close()

# ---------- Auth ----------
ADMIN_USER = "admin"
ADMIN_PASS = "1234"

def login_required(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("logged_in"):
            flash("Please log in to continue.", "warning")
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapped

# ---------- Routes ----------
@app.route("/")
def landing():
    return render_template("landing.html")

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        if username == ADMIN_USER and password == ADMIN_PASS:
            session["logged_in"] = True
            session["username"] = username
            flash("Welcome back, admin!", "success")
            return redirect(url_for("admin"))
        flash("Invalid username or password.", "danger")
    return render_template("login.html")

@app.route("/logout")
def logout():
    session.clear()
    flash("You have been logged out.", "info")
    return redirect(url_for("landing"))

@app.route("/pos")
def pos():
    return render_template("pos.html")

@app.route("/contact", methods=["POST"])
def contact():
    name = request.form.get("name", "").strip()
    flash(f"Thanks {name or 'there'}, we received your message!", "success")
    return redirect(url_for("landing") + "#contact")

# ---------- Admin CRUD on `product` ----------
@app.route("/admin")
@login_required
def admin():
    db = get_db()
    products = db.execute(
        "SELECT product_id, name, category, price, is_active "
        "FROM product ORDER BY product_id DESC"
    ).fetchall()
    return render_template("admin.html", products=products)

@app.route("/admin/products/create", methods=["POST"])
@login_required
def product_create():
    name = request.form.get("name", "").strip()
    category = request.form.get("category", "").strip()
    price_raw = request.form.get("price", "").strip()
    is_active = 1 if request.form.get("is_active") else 0
    try:
        price = float(price_raw)
        if not name or not category or price <= 0:
            raise ValueError
    except ValueError:
        flash("Please provide a valid name, category and price > 0.", "danger")
        return redirect(url_for("admin"))
    db = get_db()
    db.execute(
        "INSERT INTO product (name, category, price, is_active) VALUES (?, ?, ?, ?)",
        (name, category, price, is_active),
    )
    db.commit()
    flash(f"Product '{name}' created.", "success")
    return redirect(url_for("admin"))

@app.route("/admin/products/<int:product_id>/update", methods=["POST"])
@login_required
def product_update(product_id):
    name = request.form.get("name", "").strip()
    category = request.form.get("category", "").strip()
    price_raw = request.form.get("price", "").strip()
    is_active = 1 if request.form.get("is_active") else 0
    try:
        price = float(price_raw)
        if not name or not category or price <= 0:
            raise ValueError
    except ValueError:
        flash("Invalid product data.", "danger")
        return redirect(url_for("admin"))
    db = get_db()
    db.execute(
        "UPDATE product SET name=?, category=?, price=?, is_active=? WHERE product_id=?",
        (name, category, price, is_active, product_id),
    )
    db.commit()
    flash("Product updated.", "success")
    return redirect(url_for("admin"))

@app.route("/admin/products/<int:product_id>/delete", methods=["POST"])
@login_required
def product_delete(product_id):
    db = get_db()
    db.execute("DELETE FROM product WHERE product_id=?", (product_id,))
    db.commit()
    flash("Product deleted.", "info")
    return redirect(url_for("admin"))

if __name__ == "__main__":
    app.run(debug=True)
