/* Corrección controlada de copias de factura emitidas.
   No borra ni reescribe lecturas. No automatiza devoluciones ni regularizaciones
   de consumo/precio: esos importes necesitan validación y política de negocio.
   Por defecto solo muestra el preview. Para aplicar, completar @Aprobaciones,
   revisar los IDs y cambiar @Aplicar a 1. */
USE facturacion;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Aplicar bit = 0;
DECLARE @Aprobaciones TABLE (
    factura_copia_id int NOT NULL PRIMARY KEY,
    factura_conservada_id int NOT NULL,
    aprobacion nvarchar(300) NOT NULL
);
/* EJEMPLO DE ENTRADA, no habilitado:
INSERT INTO @Aprobaciones VALUES (123, 456, N'Aprobado por Facturación, caso INC-...');
*/

/* El registro preserva qué factura se anuló, cuál se conservó y por qué.
   Se crea una sola vez y no cambia la tabla original de facturas. */
IF OBJECT_ID(N'dbo.facturas_correcciones_auditoria', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.facturas_correcciones_auditoria (
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
    );
END;

/* Preview general de duplicados; no presupone qué factura es la válida. */
SELECT f.contrato_id, f.periodo, f.id AS factura_id, f.numero, f.estado,
       f.ejecucion_id, f.total, f.fecha_emision, f.fecha_pago
FROM dbo.facturas AS f
WHERE EXISTS (
    SELECT 1 FROM dbo.facturas AS otra
    WHERE otra.contrato_id = f.contrato_id
      AND otra.periodo = f.periodo AND otra.id <> f.id
)
ORDER BY f.periodo, f.contrato_id, f.id;

/* Preview del subconjunto aprobado que se propone anular. */
SELECT a.factura_copia_id, copia.numero AS numero_copia, copia.estado AS estado_actual,
       a.factura_conservada_id, conservada.numero AS numero_conservado,
       conservada.estado AS estado_conservado, copia.total,
       a.aprobacion,
       CASE WHEN copia.estado = 'anulada' AND au.id IS NOT NULL THEN 'ya aplicada'
            ELSE 'se anularía' END AS resultado
FROM @Aprobaciones AS a
JOIN dbo.facturas AS copia ON copia.id = a.factura_copia_id
JOIN dbo.facturas AS conservada ON conservada.id = a.factura_conservada_id
LEFT JOIN dbo.facturas_correcciones_auditoria AS au
  ON au.factura_copia_id = a.factura_copia_id AND au.accion = 'ANULAR_COPIA_EMITIDA';

IF @Aplicar = 0
BEGIN
    PRINT 'Preview únicamente. No se han modificado facturas.';
    RETURN;
END;

BEGIN TRY
    BEGIN TRANSACTION;

    IF EXISTS (
        SELECT 1
        FROM @Aprobaciones AS a
        JOIN dbo.facturas AS copia ON copia.id = a.factura_copia_id
        JOIN dbo.facturas AS conservada ON conservada.id = a.factura_conservada_id
        LEFT JOIN dbo.facturas_correcciones_auditoria AS au
          ON au.factura_copia_id = a.factura_copia_id AND au.accion = 'ANULAR_COPIA_EMITIDA'
        WHERE a.factura_copia_id = a.factura_conservada_id
           OR copia.contrato_id <> conservada.contrato_id
           OR copia.periodo <> conservada.periodo
           OR conservada.estado = 'anulada'
           OR (copia.estado <> 'emitida'
               AND NOT (copia.estado = 'anulada' AND au.id IS NOT NULL))
           OR NULLIF(LTRIM(RTRIM(a.aprobacion)), N'') IS NULL
    )
        THROW 51001, 'Precondicion fallida: IDs no forman una pareja válida o la copia no está emitida. No se aplicó ningún cambio.', 1;

    /* La tabla de auditoría hace que la operación sea repetible sin duplicar eventos. */
    UPDATE copia
       SET estado = 'anulada'
    FROM dbo.facturas AS copia
    JOIN @Aprobaciones AS a ON a.factura_copia_id = copia.id
    WHERE copia.estado = 'emitida';

    INSERT INTO dbo.facturas_correcciones_auditoria
        (factura_copia_id, factura_conservada_id, accion, aprobacion)
    SELECT a.factura_copia_id, a.factura_conservada_id,
           'ANULAR_COPIA_EMITIDA', a.aprobacion
    FROM @Aprobaciones AS a
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.facturas_correcciones_auditoria AS au
        WHERE au.factura_copia_id = a.factura_copia_id
          AND au.accion = 'ANULAR_COPIA_EMITIDA'
    );

    COMMIT TRANSACTION;
    PRINT 'Corrección aprobada aplicada; revisa la auditoría y confirma el documento/abono fuera de esta tabla.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO
