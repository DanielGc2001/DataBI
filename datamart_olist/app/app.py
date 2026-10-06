import os, time
from datetime import date, datetime
from decimal import Decimal
from flask import Flask, jsonify, request, send_from_directory
from flask.json.provider import DefaultJSONProvider
import psycopg2, psycopg2.extras
from psycopg2.pool import SimpleConnectionPool


class Provider(DefaultJSONProvider):
    @staticmethod
    def default(o):
        if isinstance(o, Decimal):
            return float(o)
        if isinstance(o, (date, datetime)):
            return o.isoformat()
        return DefaultJSONProvider.default(o)


app = Flask(__name__, static_folder="static")
app.json = Provider(app)
_pool = None


def query(sql, params=()):
    global _pool
    if _pool is None:
        _pool = SimpleConnectionPool(1, 5, host=os.getenv("DB_HOST", "db"), port=os.getenv("DB_PORT", "5432"),
                                     dbname=os.getenv("DB_NAME", "olist"), user=os.getenv("DB_USER", "postgres"),
                                     password=os.getenv("DB_PASSWORD", "postgres"))
    conn = _pool.getconn()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            return cur.fetchall()
    finally:
        conn.rollback()
        _pool.putconn(conn)


def filtros():
    a, e, c = (request.args.get(k, "") for k in ("anio", "estado", "categoria"))
    return (int(a) if a.isdigit() else None, e.upper() if len(e) == 2 else None, c or None)


@app.get("/")
def index():
    return send_from_directory("static", "index.html")


@app.get("/health")
def health():
    query("SELECT 1")
    return {"status": "ok"}


@app.get("/api/filtros")
def api_filtros():
    return {
        "anios": [r["anio"] for r in query("SELECT DISTINCT anio FROM dwh.dim_tiempo t WHERE EXISTS (SELECT 1 FROM dwh.fact_ventas f WHERE f.tiempo_key = t.tiempo_key) ORDER BY 1")],
        "estados": [r["estado"] for r in query("SELECT DISTINCT estado FROM dwh.dim_cliente ORDER BY 1")],
        "categorias": [r["categoria_en"] for r in query("SELECT DISTINCT categoria_en FROM dwh.dim_producto ORDER BY 1")],
    }


@app.get("/api/kpis")
def api_kpis():
    f = filtros()
    return query("SELECT dwh.fn_total_ventas(%s,%s,%s) AS ventas_totales, dwh.fn_total_pedidos(%s,%s,%s) AS total_pedidos, "
                 "dwh.fn_ticket_promedio(%s,%s,%s) AS ticket_promedio", f * 3)[0]


@app.get("/api/mensual")
def api_mensual():
    return jsonify(query("SELECT * FROM dwh.fn_ventas_mensuales(%s,%s,%s)", filtros()))


@app.get("/api/top-categorias")
def api_top():
    return jsonify(query("SELECT * FROM dwh.fn_top_categorias(%s,%s,%s,10)", filtros()))


@app.get("/api/detalle")
def api_detalle():
    return jsonify(query("SELECT * FROM dwh.fn_detalle_ventas(%s,%s,%s,20)", filtros()))
