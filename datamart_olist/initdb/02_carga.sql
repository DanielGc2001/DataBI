-- =====================================================================
-- 02 · CARGA: CSV -> staging (COPY) -> dimensiones -> hechos
-- =====================================================================

-- ---------- 1) CSV a staging ----------
COPY stg.customers            FROM '/data/olist_customers_dataset.csv'      WITH (FORMAT csv, HEADER true);
COPY stg.orders               FROM '/data/olist_orders_dataset.csv'         WITH (FORMAT csv, HEADER true);
COPY stg.order_items          FROM '/data/olist_order_items_dataset.csv'    WITH (FORMAT csv, HEADER true);
COPY stg.products             FROM '/data/olist_products_dataset.csv'       WITH (FORMAT csv, HEADER true);
COPY stg.category_translation FROM '/data/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true);

-- ---------- 2) dim_tiempo (generada) ----------
INSERT INTO dwh.dim_tiempo
SELECT TO_CHAR(d, 'YYYYMMDD')::INT,
       d::DATE,
       EXTRACT(YEAR    FROM d)::SMALLINT,
       EXTRACT(QUARTER FROM d)::SMALLINT,
       EXTRACT(MONTH   FROM d)::SMALLINT,
       (ARRAY['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio',
              'Agosto','Septiembre','Octubre','Noviembre','Diciembre'])[EXTRACT(MONTH FROM d)::INT],
       EXTRACT(ISODOW  FROM d)::SMALLINT
FROM generate_series('2016-01-01'::DATE, '2018-12-31'::DATE, INTERVAL '1 day') AS d;

-- ---------- 3) dim_cliente: un registro por cliente REAL (customer_unique_id) ----------
INSERT INTO dwh.dim_cliente (customer_unique_id, ciudad, estado)
SELECT DISTINCT ON (customer_unique_id)
       customer_unique_id, customer_city, UPPER(customer_state)
FROM stg.customers
ORDER BY customer_unique_id, customer_id;

-- ---------- 4) dim_producto: traduce categoría; nulos -> 'sin_categoria' ----------
INSERT INTO dwh.dim_producto (product_id, categoria_pt, categoria_en, peso_g)
SELECT p.product_id,
       p.product_category_name,
       COALESCE(t.product_category_name_english,   -- traducción
                p.product_category_name,           -- sin traducción: deja el nombre original
                'sin_categoria'),                  -- categoría nula
       p.product_weight_g::NUMERIC
FROM stg.products p
LEFT JOIN stg.category_translation t USING (product_category_name);

-- ---------- 5) fact_ventas: 1 fila por ítem de pedido ----------
INSERT INTO dwh.fact_ventas
    (tiempo_key, producto_key, cliente_key, order_id, order_item_id, order_status,
     price, freight_value, total_item, dias_entrega, entrega_tardia)
SELECT TO_CHAR(o.order_purchase_timestamp::TIMESTAMP, 'YYYYMMDD')::INT,
       p.producto_key,
       c.cliente_key,
       i.order_id,
       i.order_item_id::SMALLINT,
       o.order_status,
       i.price::NUMERIC,
       i.freight_value::NUMERIC,
       i.price::NUMERIC + i.freight_value::NUMERIC,
       CASE WHEN o.order_delivered_customer_date IS NOT NULL
            THEN o.order_delivered_customer_date::DATE - o.order_purchase_timestamp::DATE END,
       CASE WHEN o.order_delivered_customer_date IS NOT NULL
            THEN o.order_delivered_customer_date::TIMESTAMP > o.order_estimated_delivery_date::TIMESTAMP END
FROM stg.order_items i
JOIN stg.orders      o  ON o.order_id    = i.order_id
JOIN stg.customers   sc ON sc.customer_id = o.customer_id
JOIN dwh.dim_cliente c  ON c.customer_unique_id = sc.customer_unique_id
JOIN dwh.dim_producto p ON p.product_id  = i.product_id;

ANALYZE;
