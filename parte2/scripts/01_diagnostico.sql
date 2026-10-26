/* Diagnóstico de la facturación mensual. Solo lectura.
   Ejecutar en la base facturacion con sqlcmd (admite GO). */
USE facturacion;
GO
SET NOCOUNT ON;
DECLARE @periodo CHAR(7) = '2026-09';
DECLARE @inicio DATE = CONVERT(date, @periodo + '-01', 23);
DECLARE @fin DATE = EOMONTH(@inicio);

PRINT '1. Ejecuciones del periodo';
SELECT id, parametros, inicio, fin, estado, filas_procesadas, usuario, mensaje
FROM dbo.log_procesos
WHERE proceso = 'FACTURACION_MENSUAL' AND parametros = @periodo
ORDER BY inicio, id;

PRINT '2. Facturas por ejecución, estado y totales';
SELECT f.ejecucion_id, lp.estado AS estado_ejecucion, f.estado AS estado_factura,
       COUNT(*) AS facturas, COUNT(DISTINCT f.contrato_id) AS contratos,
       SUM(f.total) AS importe_total
FROM dbo.facturas AS f
LEFT JOIN dbo.log_procesos AS lp ON lp.id = f.ejecucion_id
WHERE f.periodo = @periodo
GROUP BY f.ejecucion_id, lp.estado, f.estado
ORDER BY f.ejecucion_id, f.estado;

PRINT '3. Contratos con más de una factura del periodo (IDs y estados)';
WITH repetidas AS (
    SELECT contrato_id, COUNT(*) AS numero_facturas
    FROM dbo.facturas
    WHERE periodo = @periodo
    GROUP BY contrato_id
    HAVING COUNT(*) > 1
)
SELECT c.cliente_id, f.contrato_id, f.id AS factura_id, f.numero, f.estado,
       f.ejecucion_id, f.consumo_kwh, f.precio_kwh, f.total,
       f.fecha_emision, f.fecha_pago, r.numero_facturas
FROM repetidas AS r
JOIN dbo.facturas AS f ON f.contrato_id = r.contrato_id AND f.periodo = @periodo
JOIN dbo.contratos AS c ON c.id = f.contrato_id
ORDER BY f.contrato_id, f.id;

PRINT '4. Lecturas exactamente repetidas en el periodo, con procedencia';
WITH agrupadas AS (
    SELECT contrato_id, fecha_desde, fecha_hasta, lectura_contador,
           consumo_kwh, tipo, COUNT(*) AS copias,
           STRING_AGG(CONVERT(varchar(max), CONCAT(id, ':', fichero_origen)), ' | ') AS filas_origen
    FROM dbo.lecturas
    WHERE fecha_hasta >= @inicio AND fecha_hasta <= @fin
    GROUP BY contrato_id, fecha_desde, fecha_hasta, lectura_contador, consumo_kwh, tipo
    HAVING COUNT(*) > 1
)
SELECT contrato_id, fecha_desde, fecha_hasta, lectura_contador,
       consumo_kwh, tipo, copias, copias - 1 AS filas_sobrantes, filas_origen
FROM agrupadas
ORDER BY contrato_id, fecha_desde;

PRINT '5. Suma de lecturas importadas frente a suma por lecturas distintas';
WITH lecturas_periodo AS (
    SELECT contrato_id, fecha_desde, fecha_hasta, lectura_contador, consumo_kwh, tipo
    FROM dbo.lecturas
    WHERE fecha_hasta >= @inicio AND fecha_hasta <= @fin
), brutas AS (
    SELECT contrato_id, SUM(consumo_kwh) AS consumo_cargado
    FROM lecturas_periodo GROUP BY contrato_id
), distintas AS (
    SELECT contrato_id, SUM(consumo_kwh) AS consumo_sin_repeticiones
    FROM (SELECT DISTINCT contrato_id, fecha_desde, fecha_hasta, lectura_contador, consumo_kwh, tipo
          FROM lecturas_periodo) AS d
    GROUP BY contrato_id
), sumas AS (
    SELECT b.contrato_id, b.consumo_cargado, d.consumo_sin_repeticiones
    FROM brutas AS b JOIN distintas AS d ON d.contrato_id = b.contrato_id
)
SELECT contrato_id, consumo_cargado, consumo_sin_repeticiones,
       consumo_cargado - consumo_sin_repeticiones AS exceso_por_repeticion
FROM sumas
WHERE consumo_cargado <> consumo_sin_repeticiones
ORDER BY contrato_id;

PRINT '6. Precios válidos y precios guardados en facturas';
SELECT t.codigo, p.precio_kwh, p.termino_fijo_mes, p.vigente_desde, p.vigente_hasta
FROM dbo.tarifas AS t
JOIN dbo.tarifas_precios AS p ON p.tarifa_id = t.id
ORDER BY t.id, p.vigente_desde;
SELECT t.codigo, f.precio_kwh, f.estado, COUNT(*) AS facturas,
       COUNT(DISTINCT f.contrato_id) AS contratos,
       COUNT(DISTINCT c.cliente_id) AS clientes, SUM(f.total) AS importe_total
FROM dbo.facturas AS f
JOIN dbo.contratos AS c ON c.id = f.contrato_id
JOIN dbo.tarifas AS t ON t.id = c.tarifa_id
WHERE f.periodo = @periodo
GROUP BY t.codigo, f.precio_kwh, f.estado
ORDER BY t.codigo, f.precio_kwh, f.estado;

PRINT '7. Contratos y clientes con TEMPO_FIJA afectados';
SELECT COUNT(DISTINCT c.cliente_id) AS clientes,
       COUNT(DISTINCT c.id) AS contratos,
       COUNT(f.id) AS facturas,
       SUM(f.total) AS importe_facturado
FROM dbo.facturas AS f
JOIN dbo.contratos AS c ON c.id = f.contrato_id
JOIN dbo.tarifas AS t ON t.id = c.tarifa_id
WHERE f.periodo = @periodo AND t.codigo = 'TEMPO_FIJA';

PRINT '8. Comparativa de lecturas/facturas del contrato del cliente 119';
SELECT f.id, f.numero, f.periodo, f.consumo_kwh, f.total, f.estado, f.ejecucion_id
FROM dbo.facturas AS f
JOIN dbo.contratos AS c ON c.id = f.contrato_id
WHERE c.cliente_id = 119 AND f.periodo IN ('2026-08', @periodo)
ORDER BY f.periodo, f.id;
SELECT l.contrato_id, l.fecha_desde, l.fecha_hasta, l.consumo_kwh,
       l.tipo, l.fichero_origen
FROM dbo.lecturas AS l
JOIN dbo.contratos AS c ON c.id = l.contrato_id
WHERE c.cliente_id = 119 AND l.fecha_hasta >= '2026-08-01'
  AND l.fecha_hasta < '2026-10-01'
ORDER BY l.fecha_hasta, l.id;

PRINT '9. Reclamaciones del periodo de incidencia';
SELECT r.id, r.fecha, r.cliente_id, r.canal, r.texto
FROM dbo.reclamaciones AS r
ORDER BY r.fecha, r.id;

PRINT '10. Clientes únicos afectados por la unión de las tres causas confirmadas';
WITH ejecuciones_periodo AS (
    SELECT id FROM dbo.log_procesos
    WHERE proceso = 'FACTURACION_MENSUAL' AND parametros = @periodo
), contratos_factura_duplicada AS (
    SELECT f.contrato_id
    FROM dbo.facturas AS f
    WHERE f.periodo = @periodo
      AND f.ejecucion_id IN (SELECT id FROM ejecuciones_periodo)
    GROUP BY f.contrato_id
    HAVING COUNT(*) > 1
), contratos_lectura_duplicada AS (
    SELECT contrato_id
    FROM dbo.lecturas
    WHERE fecha_hasta >= @inicio AND fecha_hasta <= @fin
    GROUP BY contrato_id, fecha_desde, fecha_hasta, lectura_contador, consumo_kwh, tipo
    HAVING COUNT(*) > 1
), clientes_afectados AS (
    SELECT DISTINCT c.cliente_id
    FROM contratos_factura_duplicada AS d
    JOIN dbo.contratos AS c ON c.id = d.contrato_id
    UNION
    SELECT DISTINCT c.cliente_id
    FROM contratos_lectura_duplicada AS d
    JOIN dbo.contratos AS c ON c.id = d.contrato_id
    UNION
    SELECT DISTINCT c.cliente_id
    FROM dbo.facturas AS f
    JOIN dbo.contratos AS c ON c.id = f.contrato_id
    JOIN dbo.tarifas AS t ON t.id = c.tarifa_id
    WHERE f.periodo = @periodo AND t.codigo = 'TEMPO_FIJA'
      AND f.precio_kwh = 0.149000
)
SELECT COUNT(*) AS clientes_unicos_afectados
FROM clientes_afectados;
GO
