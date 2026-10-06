-- =====================================================================
-- 03 · FUNCIONES Y VISTAS que alimentan el dashboard
-- (los pedidos 'canceled' y 'unavailable' no cuentan como venta)
-- =====================================================================

-- KPI 1: Ventas totales
CREATE OR REPLACE FUNCTION dwh.fn_total_ventas(
    p_anio INT DEFAULT NULL, p_estado CHAR(2) DEFAULT NULL, p_categoria VARCHAR DEFAULT NULL)
RETURNS NUMERIC AS $$
    SELECT COALESCE(SUM(f.price), 0)
    FROM dwh.fact_ventas f
    JOIN dwh.dim_tiempo   t ON t.tiempo_key   = f.tiempo_key
    JOIN dwh.dim_cliente  c ON c.cliente_key  = f.cliente_key
    JOIN dwh.dim_producto p ON p.producto_key = f.producto_key
    WHERE f.order_status NOT IN ('canceled','unavailable')
      AND (p_anio      IS NULL OR t.anio         = p_anio)
      AND (p_estado    IS NULL OR c.estado       = p_estado)
      AND (p_categoria IS NULL OR p.categoria_en = p_categoria);
$$ LANGUAGE sql STABLE;

-- KPI 2: Total de pedidos
CREATE OR REPLACE FUNCTION dwh.fn_total_pedidos(
    p_anio INT DEFAULT NULL, p_estado CHAR(2) DEFAULT NULL, p_categoria VARCHAR DEFAULT NULL)
RETURNS BIGINT AS $$
    SELECT COUNT(DISTINCT f.order_id)
    FROM dwh.fact_ventas f
    JOIN dwh.dim_tiempo   t ON t.tiempo_key   = f.tiempo_key
    JOIN dwh.dim_cliente  c ON c.cliente_key  = f.cliente_key
    JOIN dwh.dim_producto p ON p.producto_key = f.producto_key
    WHERE f.order_status NOT IN ('canceled','unavailable')
      AND (p_anio      IS NULL OR t.anio         = p_anio)
      AND (p_estado    IS NULL OR c.estado       = p_estado)
      AND (p_categoria IS NULL OR p.categoria_en = p_categoria);
$$ LANGUAGE sql STABLE;

-- KPI 3: Ticket promedio = ventas / pedidos
CREATE OR REPLACE FUNCTION dwh.fn_ticket_promedio(
    p_anio INT DEFAULT NULL, p_estado CHAR(2) DEFAULT NULL, p_categoria VARCHAR DEFAULT NULL)
RETURNS NUMERIC AS $$
    SELECT ROUND(dwh.fn_total_ventas(p_anio, p_estado, p_categoria)
                 / NULLIF(dwh.fn_total_pedidos(p_anio, p_estado, p_categoria), 0), 2);
$$ LANGUAGE sql STABLE;

-- Gráfico de líneas: KPIs por mes
CREATE OR REPLACE FUNCTION dwh.fn_ventas_mensuales(
    p_anio INT DEFAULT NULL, p_estado CHAR(2) DEFAULT NULL, p_categoria VARCHAR DEFAULT NULL)
RETURNS TABLE (
    periodo_anio SMALLINT, periodo_mes SMALLINT, mes_nombre VARCHAR(15),
    ventas_totales NUMERIC, total_pedidos BIGINT, ticket_promedio NUMERIC)
AS $$
    SELECT t.anio, t.mes, t.nombre_mes,
           SUM(f.price),
           COUNT(DISTINCT f.order_id),
           ROUND(SUM(f.price) / NULLIF(COUNT(DISTINCT f.order_id), 0), 2)
    FROM dwh.fact_ventas f
    JOIN dwh.dim_tiempo   t ON t.tiempo_key   = f.tiempo_key
    JOIN dwh.dim_cliente  c ON c.cliente_key  = f.cliente_key
    JOIN dwh.dim_producto p ON p.producto_key = f.producto_key
    WHERE f.order_status NOT IN ('canceled','unavailable')
      AND (p_anio      IS NULL OR t.anio         = p_anio)
      AND (p_estado    IS NULL OR c.estado       = p_estado)
      AND (p_categoria IS NULL OR p.categoria_en = p_categoria)
    GROUP BY t.anio, t.mes, t.nombre_mes
    ORDER BY t.anio, t.mes;
$$ LANGUAGE sql STABLE;

-- Gráfico de barras: top categorías
CREATE OR REPLACE VIEW dwh.v_top_categorias AS
SELECT p.categoria_en,
       SUM(f.price)               AS ventas_totales,
       COUNT(DISTINCT f.order_id) AS total_pedidos
FROM dwh.fact_ventas f
JOIN dwh.dim_producto p ON p.producto_key = f.producto_key
WHERE f.order_status NOT IN ('canceled','unavailable')
GROUP BY p.categoria_en
ORDER BY ventas_totales DESC;

-- Tabla de detalle
CREATE OR REPLACE VIEW dwh.v_detalle_ventas AS
SELECT f.order_id, t.fecha, p.categoria_en, c.estado AS estado_cliente,
       f.price, f.freight_value, f.order_status
FROM dwh.fact_ventas f
JOIN dwh.dim_tiempo   t ON t.tiempo_key   = f.tiempo_key
JOIN dwh.dim_producto p ON p.producto_key = f.producto_key
JOIN dwh.dim_cliente  c ON c.cliente_key  = f.cliente_key;

-- Gráfico de barras con filtros: top categorías
CREATE OR REPLACE FUNCTION dwh.fn_top_categorias(
    p_anio INT DEFAULT NULL, p_estado CHAR(2) DEFAULT NULL,
    p_categoria VARCHAR DEFAULT NULL, p_limite INT DEFAULT 10)
RETURNS TABLE (categoria VARCHAR(80), ventas_totales NUMERIC, total_pedidos BIGINT)
AS $$
    SELECT p.categoria_en, SUM(f.price), COUNT(DISTINCT f.order_id)
    FROM dwh.fact_ventas f
    JOIN dwh.dim_tiempo   t ON t.tiempo_key   = f.tiempo_key
    JOIN dwh.dim_cliente  c ON c.cliente_key  = f.cliente_key
    JOIN dwh.dim_producto p ON p.producto_key = f.producto_key
    WHERE f.order_status NOT IN ('canceled','unavailable')
      AND (p_anio      IS NULL OR t.anio         = p_anio)
      AND (p_estado    IS NULL OR c.estado       = p_estado)
      AND (p_categoria IS NULL OR p.categoria_en = p_categoria)
    GROUP BY p.categoria_en
    ORDER BY SUM(f.price) DESC
    LIMIT p_limite;
$$ LANGUAGE sql STABLE;

-- Tabla de detalle con filtros
CREATE OR REPLACE FUNCTION dwh.fn_detalle_ventas(
    p_anio INT DEFAULT NULL, p_estado CHAR(2) DEFAULT NULL,
    p_categoria VARCHAR DEFAULT NULL, p_limite INT DEFAULT 20)
RETURNS TABLE (order_id VARCHAR(40), order_item_id SMALLINT, fecha DATE, categoria VARCHAR(80),
               estado_cliente CHAR(2), price NUMERIC, freight_value NUMERIC, order_status VARCHAR(20))
AS $$
    SELECT f.order_id, f.order_item_id, t.fecha, p.categoria_en, c.estado,
           f.price, f.freight_value, f.order_status
    FROM dwh.fact_ventas f
    JOIN dwh.dim_tiempo   t ON t.tiempo_key   = f.tiempo_key
    JOIN dwh.dim_cliente  c ON c.cliente_key  = f.cliente_key
    JOIN dwh.dim_producto p ON p.producto_key = f.producto_key
    WHERE f.order_status NOT IN ('canceled','unavailable')
      AND (p_anio      IS NULL OR t.anio         = p_anio)
      AND (p_estado    IS NULL OR c.estado       = p_estado)
      AND (p_categoria IS NULL OR p.categoria_en = p_categoria)
    ORDER BY t.fecha DESC, f.price DESC
    LIMIT p_limite;
$$ LANGUAGE sql STABLE;
