/* Corrección controlada de copias de factura emitidas.
   El modo inicial es solo lectura y no crea objetos permanentes.
   Para aplicar una anulación, completar #Aprobaciones, validar los IDs y poner
   @Aplicar = 1. No automatiza devoluciones ni regularizaciones de lecturas/precio. */
USE facturacion;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @periodo char(7) = '2026-09';
DECLARE @Aplicar bit = 0;
CREATE TABLE #Aprobaciones (
    factura_copia_id int NOT NULL PRIMARY KEY,
    factura_conservada_id int NOT NULL,
    aprobacion nvarchar(300) NOT NULL
);
/* EJEMPLO, desactivado:
INSERT INTO #Aprobaciones VALUES (123, 456, N'Aprobado por Facturación, caso INC-...');
*/

/* Preview general: no presupone qué factura conservar. */
SELECT f.contrato_id, f.periodo, f.id AS factura_id, f.numero, f.estado,
       f.ejecucion_id, f.total, f.fecha_emision, f.fecha_pago
FROM dbo.facturas AS f
WHERE f.periodo = @periodo
  AND EXISTS (
      SELECT 1 FROM dbo.facturas AS otra
      WHERE otra.contrato_id = f.contrato_id
        AND otra.periodo = f.periodo AND otra.id <> f.id
  )
ORDER BY f.contrato_id, f.id;

/* Preview de las anulaciones que se han cargado explícitamente para aprobación. */
SELECT a.factura_copia_id, copia.numero AS numero_copia, copia.estado AS estado_actual,
       a.factura_conservada_id, conservada.numero AS numero_conservado,
       conservada.estado AS estado_conservado, copia.total, a.aprobacion
FROM #Aprobaciones AS a
JOIN dbo.facturas AS copia ON copia.id = a.factura_copia_id
JOIN dbo.facturas AS conservada ON conservada.id = a.factura_conservada_id;

IF @Aplicar = 0
BEGIN
    PRINT 'Vista previa solamente. No se han cambiado facturas ni objetos permanentes.';
    RETURN;
END;

IF NOT EXISTS (SELECT 1 FROM #Aprobaciones)
    THROW 51020, 'No hay anulaciones aprobadas. No se aplicó ningún cambio.', 1;

IF EXISTS (
    SELECT 1
    FROM #Aprobaciones AS a
    LEFT JOIN dbo.facturas AS copia ON copia.id = a.factura_copia_id
    LEFT JOIN dbo.facturas AS conservada ON conservada.id = a.factura_conservada_id
    WHERE copia.id IS NULL OR conservada.id IS NULL
       OR copia.id = conservada.id
       OR copia.contrato_id <> conservada.contrato_id
       OR copia.periodo <> conservada.periodo
       OR conservada.estado = 'anulada'
       OR (copia.estado <> 'emitida' AND copia.estado <> 'anulada')
       OR NULLIF(LTRIM(RTRIM(a.aprobacion)), N'') IS NULL
)
    THROW 51021, 'Precondición fallida: revisa IDs, estados y referencia de aprobación.', 1;

/* El DDL solo se ejecuta en modo Aplicar. La escritura va en otro batch dinámico
   para compilar referencias a la tabla después de crearla. */
IF OBJECT_ID(N'dbo.facturas_correcciones_auditoria', N'U') IS NULL
BEGIN
    EXEC(N'CREATE TABLE dbo.facturas_correcciones_auditoria (
        id bigint IDENTITY(1,1) NOT NULL CONSTRAINT PK_facturas_correcciones_auditoria PRIMARY KEY,
        factura_copia_id int NOT NULL,
        factura_conservada_id int NOT NULL,
        accion varchar(30) NOT NULL,
        aprobacion nvarchar(300) NOT NULL,
        aplicado_en datetime2(0) NOT NULL CONSTRAINT DF_facturas_corr_aplicado DEFAULT SYSUTCDATETIME(),
        aplicado_por sysname NOT NULL CONSTRAINT DF_facturas_corr_usuario DEFAULT SUSER_SNAME(),
        CONSTRAINT UQ_facturas_corr_copia_accion UNIQUE (factura_copia_id, accion),
        CONSTRAINT FK_facturas_corr_copia FOREIGN KEY (factura_copia_id) REFERENCES dbo.facturas(id),
        CONSTRAINT FK_facturas_corr_conservada FOREIGN KEY (factura_conservada_id) REFERENCES dbo.facturas(id)
    );');
END;

EXEC sys.sp_executesql N'
BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM #Aprobaciones AS a
        JOIN dbo.facturas AS copia ON copia.id = a.factura_copia_id
        JOIN dbo.facturas AS conservada ON conservada.id = a.factura_conservada_id
        LEFT JOIN dbo.facturas_correcciones_auditoria AS au
          ON au.factura_copia_id = a.factura_copia_id AND au.accion = ''ANULAR_COPIA_EMITIDA''
        WHERE copia.contrato_id <> conservada.contrato_id
           OR copia.periodo <> conservada.periodo
           OR conservada.estado = ''anulada''
           OR (copia.estado <> ''emitida''
               AND NOT (copia.estado = ''anulada'' AND au.id IS NOT NULL))
    )
        THROW 51022, ''Precondición fallida o la copia pagada/no emitida no es anulable por este script.'', 1;

    UPDATE copia
       SET estado = ''anulada''
    FROM dbo.facturas AS copia
    JOIN #Aprobaciones AS a ON a.factura_copia_id = copia.id
    WHERE copia.estado = ''emitida'';

    INSERT INTO dbo.facturas_correcciones_auditoria
        (factura_copia_id, factura_conservada_id, accion, aprobacion)
    SELECT a.factura_copia_id, a.factura_conservada_id,
           ''ANULAR_COPIA_EMITIDA'', a.aprobacion
    FROM #Aprobaciones AS a
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.facturas_correcciones_auditoria AS au
        WHERE au.factura_copia_id = a.factura_copia_id
          AND au.accion = ''ANULAR_COPIA_EMITIDA''
    );

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;';
PRINT 'Anulación aprobada aplicada y auditada.';
GO
