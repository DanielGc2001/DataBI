-- =====================================================================
-- 01 · Esquemas, STAGING (CSV tal cual) y MODELO DIMENSIONAL
-- Granularidad de fact_ventas: UNA FILA = UN ÍTEM (producto) VENDIDO
-- DENTRO DE UN PEDIDO (order_id + order_item_id).
-- =====================================================================
CREATE SCHEMA stg;
CREATE SCHEMA dwh;

-- ---------- STAGING: todo en TEXT, mismo orden que los CSV ----------
CREATE TABLE stg.customers (
    customer_id TEXT, customer_unique_id TEXT, customer_zip_code_prefix TEXT,
    customer_city TEXT, customer_state TEXT);

CREATE TABLE stg.orders (
    order_id TEXT, customer_id TEXT, order_status TEXT,
    order_purchase_timestamp TEXT, order_approved_at TEXT,
    order_delivered_carrier_date TEXT, order_delivered_customer_date TEXT,
    order_estimated_delivery_date TEXT);

CREATE TABLE stg.order_items (
    order_id TEXT, order_item_id TEXT, product_id TEXT, seller_id TEXT,
    shipping_limit_date TEXT, price TEXT, freight_value TEXT);

CREATE TABLE stg.products (
    product_id TEXT, product_category_name TEXT, product_name_lenght TEXT,
    product_description_lenght TEXT, product_photos_qty TEXT, product_weight_g TEXT,
    product_length_cm TEXT, product_height_cm TEXT, product_width_cm TEXT);

CREATE TABLE stg.category_translation (
    product_category_name TEXT, product_category_name_english TEXT);

-- ---------- DIMENSIONES ----------
CREATE TABLE dwh.dim_tiempo (
    tiempo_key  INT         PRIMARY KEY,               -- YYYYMMDD
    fecha       DATE        NOT NULL UNIQUE,
    anio        SMALLINT    NOT NULL CHECK (anio BETWEEN 2000 AND 2100),
    trimestre   SMALLINT    NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    mes         SMALLINT    NOT NULL CHECK (mes BETWEEN 1 AND 12),
    nombre_mes  VARCHAR(15) NOT NULL,
    dia_semana  SMALLINT    NOT NULL CHECK (dia_semana BETWEEN 1 AND 7)  -- 1 = lunes
);

CREATE TABLE dwh.dim_producto (
    producto_key  SERIAL        PRIMARY KEY,
    product_id    VARCHAR(40)   NOT NULL UNIQUE,
    categoria_pt  VARCHAR(80),
    categoria_en  VARCHAR(80)   NOT NULL DEFAULT 'sin_categoria',
    peso_g        NUMERIC(10,2) CHECK (peso_g IS NULL OR peso_g >= 0)
);

CREATE TABLE dwh.dim_cliente (
    cliente_key         SERIAL      PRIMARY KEY,
    customer_unique_id  VARCHAR(40) NOT NULL UNIQUE,   -- cliente real
    ciudad              VARCHAR(80),
    estado              CHAR(2)     CHECK (estado ~ '^[A-Z]{2}$')
);

-- ---------- TABLA DE HECHOS ----------
CREATE TABLE dwh.fact_ventas (
    venta_key       BIGSERIAL     PRIMARY KEY,
    tiempo_key      INT           NOT NULL REFERENCES dwh.dim_tiempo(tiempo_key),
    producto_key    INT           NOT NULL REFERENCES dwh.dim_producto(producto_key),
    cliente_key     INT           NOT NULL REFERENCES dwh.dim_cliente(cliente_key),
    order_id        VARCHAR(40)   NOT NULL,
    order_item_id   SMALLINT      NOT NULL CHECK (order_item_id > 0),
    order_status    VARCHAR(20)   NOT NULL
        CHECK (order_status IN ('delivered','shipped','canceled','unavailable',
                                'invoiced','processing','created','approved')),
    price           NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    freight_value   NUMERIC(10,2) NOT NULL CHECK (freight_value >= 0),
    total_item      NUMERIC(10,2) NOT NULL CHECK (total_item >= 0),      -- price + freight_value
    dias_entrega    INT           CHECK (dias_entrega IS NULL OR dias_entrega >= 0),
    entrega_tardia  BOOLEAN,                                             -- NULL si no se entregó
    CONSTRAINT uq_fact_pedido_item UNIQUE (order_id, order_item_id)
);

CREATE INDEX idx_fact_tiempo   ON dwh.fact_ventas(tiempo_key);
CREATE INDEX idx_fact_producto ON dwh.fact_ventas(producto_key);
CREATE INDEX idx_fact_cliente  ON dwh.fact_ventas(cliente_key);
