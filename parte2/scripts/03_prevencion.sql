/* Sustituye el procedimiento de facturación por una versión conservadora.
   - Serializa ejecuciones del mismo periodo.
   - Ejecuta todas las facturas en una transacción.
   - Rechaza periodos con facturas previas o lecturas exactas duplicadas.
   - Rechaza meses con más de un precio aplicable; exige dato/prorrateo resuelto.
   No corrige datos históricos ni reemplaza la carga idempotente de ficheros. */
USE facturacion;
GO
CREATE OR ALTER PROCEDURE dbo.sp_facturar_periodo
    @periodo char(7)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @inicio date;
    DECLARE @fin date;
    DECLARE @ejecucion_id int;
    DECLARE @resultado_bloqueo int;
    DECLARE @recurso_bloqueo nvarchar(255);
    DECLARE @contrato_id int;
    DECLARE @tarifa_id int;
    DECLARE @consumo decimal(12,3);
    DECLARE @precio decimal(10,6);
    DECLARE @fijo decimal(10,2);
    DECLARE @importe decimal(12,2);
    DECLARE @numero int;
    DECLARE @procesados int = 0;

    IF @periodo IS NULL OR @periodo NOT LIKE '[12][0-9][0-9][0-9]-[01][0-9]'
       OR TRY_CONVERT(date, @periodo + '-01', 23) IS NULL
       OR SUBSTRING(@periodo, 6, 2) NOT BETWEEN '01' AND '12'
        THROW 51010, 'Periodo inválido. Usa YYYY-MM.', 1;

    SET @inicio = CONVERT(date, @periodo + '-01', 23);
    SET @fin = EOMONTH(@inicio);

    BEGIN TRY
        BEGIN TRANSACTION;
        SET @recurso_bloqueo = CONCAT(N'facturacion-periodo-', @periodo);
        EXEC @resultado_bloqueo = sys.sp_getapplock
            @Resource = @recurso_bloqueo,
            @LockMode = 'Exclusive', @LockOwner = 'Transaction', @LockTimeout = 0;
        IF @resultado_bloqueo < 0
            THROW 51011, 'No se pudo adquirir el bloqueo del periodo.', 1;

        IF EXISTS (
            SELECT 1 FROM dbo.facturas WITH (UPDLOCK, HOLDLOCK)
            WHERE periodo = @periodo
        )
            THROW 51012, 'Ya existen facturas para este periodo. Requiere conciliación antes de reintentar.', 1;

        IF EXISTS (
            SELECT 1
            FROM dbo.lecturas WITH (TABLOCKX, HOLDLOCK)
            WHERE fecha_hasta >= @inicio AND fecha_hasta <= @fin
            GROUP BY contrato_id, fecha_desde, fecha_hasta, lectura_contador, consumo_kwh, tipo
            HAVING COUNT(*) > 1
        )
            THROW 51013, 'Hay lecturas exactas duplicadas en el periodo. Detén facturación hasta conciliarlas.', 1;

        /* Una tarifa debe tener exactamente un precio durante todo el mes.
           Si cambia a mitad del mes, hacen falta consumos por tramo o regla aprobada. */
        IF EXISTS (
            SELECT c.tarifa_id
            FROM dbo.contratos AS c
            WHERE c.fecha_alta <= @fin AND (c.fecha_baja IS NULL OR c.fecha_baja >= @inicio)
            GROUP BY c.tarifa_id
            HAVING (SELECT COUNT(*) FROM dbo.tarifas_precios AS p
                    WHERE p.tarifa_id = c.tarifa_id
                      AND p.vigente_desde <= @fin
                      AND (p.vigente_hasta IS NULL OR p.vigente_hasta >= @inicio)) <> 1
                OR NOT EXISTS (SELECT 1 FROM dbo.tarifas_precios AS p
                    WHERE p.tarifa_id = c.tarifa_id
                      AND p.vigente_desde <= @inicio
                      AND (p.vigente_hasta IS NULL OR p.vigente_hasta >= @fin))
        )
            THROW 51014, 'Hay tarifas sin un precio único válido para todo el periodo; requiere resolución previa.', 1;

        INSERT INTO dbo.log_procesos (proceso, parametros, inicio, estado, usuario)
        VALUES ('FACTURACION_MENSUAL', @periodo, SYSDATETIME(), 'EN_CURSO', SUSER_SNAME());
        SET @ejecucion_id = CONVERT(int, SCOPE_IDENTITY());

        DECLARE contratos_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT id, tarifa_id
            FROM dbo.contratos
            WHERE fecha_alta <= @fin
              AND (fecha_baja IS NULL OR fecha_baja >= @inicio)
            ORDER BY id;

        OPEN contratos_cur;
        FETCH NEXT FROM contratos_cur INTO @contrato_id, @tarifa_id;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @consumo = COALESCE(SUM(consumo_kwh), 0)
            FROM dbo.lecturas
            WHERE contrato_id = @contrato_id
              AND fecha_hasta >= @inicio AND fecha_hasta <= @fin;

            SELECT @precio = precio_kwh, @fijo = termino_fijo_mes
            FROM dbo.tarifas_precios
            WHERE tarifa_id = @tarifa_id
              AND vigente_desde <= @inicio
              AND (vigente_hasta IS NULL OR vigente_hasta >= @fin);

            SET @importe = ROUND(@consumo * @precio, 2);
            SET @numero = NEXT VALUE FOR dbo.seq_factura;
            INSERT INTO dbo.facturas
                (numero, contrato_id, periodo, fecha_desde, fecha_hasta, consumo_kwh,
                 precio_kwh, importe_energia, importe_fijo, total, estado, ejecucion_id, fecha_creacion)
            VALUES
                (CONCAT('F', LEFT(@periodo, 4), '-', FORMAT(@numero, '000000')),
                 @contrato_id, @periodo, @inicio, @fin, @consumo, @precio,
                 @importe, @fijo, @importe + @fijo, 'borrador', @ejecucion_id, SYSDATETIME());

            SET @procesados += 1;
            FETCH NEXT FROM contratos_cur INTO @contrato_id, @tarifa_id;
        END;
        CLOSE contratos_cur;
        DEALLOCATE contratos_cur;

        UPDATE dbo.log_procesos
        SET fin = SYSDATETIME(), estado = 'OK', filas_procesadas = @procesados
        WHERE id = @ejecucion_id;
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'contratos_cur') >= 0 CLOSE contratos_cur;
        IF CURSOR_STATUS('local', 'contratos_cur') > -3 DEALLOCATE contratos_cur;
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO

/* Monitor: ejecuciones colgadas o fallidas del último día. */
SELECT id, proceso, parametros, inicio, fin, estado, usuario, mensaje
FROM dbo.log_procesos
WHERE proceso = 'FACTURACION_MENSUAL'
  AND (estado <> 'OK' OR inicio >= DATEADD(day, -1, SYSDATETIME()))
ORDER BY inicio DESC, id DESC;
GO
