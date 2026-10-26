/* Prevención T-SQL:
   1. La ingesta debe invocar sp_register_reading_once para que reintentar una
      lectura idéntica no inserte otra fila y una revisión distinta quede en conflicto.
   2. La facturación queda serializada, atómica y fail-closed ante estado previo,
      lecturas duplicadas o precio que cambie dentro del mes.
   El procedimiento de ingesta debe ser usado por el cargador; un INSERT directo
   puede eludirlo. El prorrateo requiere una regla y consumos por tramo. */
USE facturacion;
GO
CREATE OR ALTER PROCEDURE dbo.sp_register_reading_once
    @contract_id int,
    @period_start date,
    @period_end date,
    @meter_reading int,
    @period_consumption decimal(12,3),
    @reading_type varchar(10),
    @source_file varchar(60)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @period_end < @period_start OR @reading_type NOT IN ('real', 'estimada')
        THROW 51001, 'Periodo o tipo de lectura inválido.', 1;

    DECLARE @lock_result int;
    DECLARE @lock_resource nvarchar(255) = CONCAT(
        N'reading-', @contract_id, N'-', CONVERT(char(8), @period_start, 112),
        N'-', CONVERT(char(8), @period_end, 112));
    DECLARE @reading_id int;
    DECLARE @was_repeat bit = 0;

    BEGIN TRY
        BEGIN TRANSACTION;
        EXEC @lock_result = sys.sp_getapplock
            @Resource = @lock_resource, @LockMode = 'Exclusive',
            @LockOwner = 'Transaction', @LockTimeout = 10000;
        IF @lock_result < 0
            THROW 51002, 'No se pudo bloquear la clave de lectura para la ingesta.', 1;

        /* Para un contrato y periodo solo se admite la misma lectura exacta.
           Una corrección con valores distintos requiere resolución explícita. */
        IF EXISTS (
            SELECT 1
            FROM dbo.lecturas WITH (UPDLOCK, HOLDLOCK)
            WHERE contrato_id = @contract_id
              AND fecha_desde = @period_start AND fecha_hasta = @period_end
              AND (lectura_contador <> @meter_reading
                   OR consumo_kwh <> @period_consumption
                   OR tipo <> @reading_type)
        )
            THROW 51003, 'Ya hay una lectura distinta para el contrato y periodo; requiere revisión.', 1;

        SELECT @reading_id = MIN(id)
        FROM dbo.lecturas WITH (UPDLOCK, HOLDLOCK)
        WHERE contrato_id = @contract_id
          AND fecha_desde = @period_start AND fecha_hasta = @period_end
          AND lectura_contador = @meter_reading
          AND consumo_kwh = @period_consumption
          AND tipo = @reading_type;

        IF @reading_id IS NULL
        BEGIN
            INSERT INTO dbo.lecturas
                (contrato_id, fecha_desde, fecha_hasta, lectura_contador,
                 consumo_kwh, tipo, fichero_origen, fecha_carga)
            VALUES
                (@contract_id, @period_start, @period_end, @meter_reading,
                 @period_consumption, @reading_type, @source_file, SYSDATETIME());
            SET @reading_id = CONVERT(int, SCOPE_IDENTITY());
        END
        ELSE
            SET @was_repeat = 1;

        COMMIT TRANSACTION;
        SELECT @reading_id AS reading_id, @was_repeat AS was_repeat;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
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
