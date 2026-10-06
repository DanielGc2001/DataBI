-- =====================================================================
-- CONSULTAS DE VALIDACIÓN
-- Ejecutar:  docker compose exec db psql -U postgres -d olist -f /validacion/validacion.sql
-- =====================================================================
\echo '=== 1. CANTIDAD DE REGISTROS (staging vs. modelo) ==='
SELECT 'stg.order_items' AS tabla, COUNT(*) AS filas FROM stg.order_items
UNION ALL SELECT 'dwh.fact_ventas',  COUNT(*) FROM dwh.fact_ventas
UNION ALL SELECT 'stg.customers (customer_unique_id distintos)', COUNT(DISTINCT customer_unique_id) FROM stg.customers
UNION ALL SELECT 'dwh.dim_cliente',  COUNT(*) FROM dwh.dim_cliente
UNION ALL SELECT 'stg.products',     COUNT(*) FROM stg.products
UNION ALL SELECT 'dwh.dim_producto', COUNT(*) FROM dwh.dim_producto
UNION ALL SELECT 'dwh.dim_tiempo',   COUNT(*) FROM dwh.dim_tiempo;

\echo '=== 2. INTEGRIDAD: hechos sin dimensión (debe dar 0 en todas) ==='
SELECT
  (SELECT COUNT(*) FROM dwh.fact_ventas f LEFT JOIN dwh.dim_tiempo   d ON d.tiempo_key   = f.tiempo_key   WHERE d.tiempo_key   IS NULL) AS huerfanos_tiempo,
  (SELECT COUNT(*) FROM dwh.fact_ventas f LEFT JOIN dwh.dim_producto d ON d.producto_key = f.producto_key WHERE d.producto_key IS NULL) AS huerfanos_producto,
  (SELECT COUNT(*) FROM dwh.fact_ventas f LEFT JOIN dwh.dim_cliente  d ON d.cliente_key  = f.cliente_key  WHERE d.cliente_key  IS NULL) AS huerfanos_cliente;

\echo '=== 3. INTEGRIDAD: granularidad sin duplicados (debe dar 0) ==='
SELECT COUNT(*) AS duplicados_pedido_item FROM (
  SELECT order_id, order_item_id FROM dwh.fact_ventas GROUP BY 1,2 HAVING COUNT(*) > 1) x;

\echo '=== 4. VALORES NULOS RELEVANTES ==='
SELECT
  COUNT(*) FILTER (WHERE dias_entrega   IS NULL) AS sin_fecha_entrega,
  COUNT(*) FILTER (WHERE entrega_tardia IS NULL) AS sin_dato_entrega_tardia,
  COUNT(*) FILTER (WHERE price IS NULL OR freight_value IS NULL) AS sin_precio_o_flete
FROM dwh.fact_ventas;
SELECT COUNT(*) FILTER (WHERE categoria_pt IS NULL) AS productos_sin_categoria,
       COUNT(*) FILTER (WHERE peso_g IS NULL)       AS productos_sin_peso
FROM dwh.dim_producto;

\echo '=== 5. TOTALES: staging vs. hechos (deben coincidir) ==='
SELECT (SELECT ROUND(SUM(price::NUMERIC),2)         FROM stg.order_items) AS ventas_staging,
       (SELECT ROUND(SUM(price),2)                  FROM dwh.fact_ventas) AS ventas_dwh,
       (SELECT ROUND(SUM(freight_value::NUMERIC),2) FROM stg.order_items) AS flete_staging,
       (SELECT ROUND(SUM(freight_value),2)          FROM dwh.fact_ventas) AS flete_dwh;

\echo '=== 6. KPIs PRINCIPALES (sin filtros) ==='
SELECT dwh.fn_total_ventas()    AS ventas_totales,
       dwh.fn_total_pedidos()   AS total_pedidos,
       dwh.fn_ticket_promedio() AS ticket_promedio;

\echo '=== 7. VENTAS POR MES (año 2017) ==='
SELECT * FROM dwh.fn_ventas_mensuales(2017);

\echo '=== 8. TOP 5 CATEGORÍAS ==='
SELECT * FROM dwh.v_top_categorias LIMIT 5;
