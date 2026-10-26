# Informe de incidencia de facturación — septiembre de 2026

## Resumen para Facturación

La facturación de septiembre se ejecutó dos veces después de que Jenkins agotara el tiempo de espera a los 45 minutos. El procedimiento no protegía el periodo frente a reintentos y dejaba las facturas ya insertadas aunque la ejecución no terminara. Además, se cargaron dos veces 44 lecturas de la distribuidora y el procedimiento aplicó a todo el mes el precio de `TEMPO_FIJA` vigente al ejecutar.

Hay tres incidencias confirmadas y una reclamación que requiere comprobación externa. La unión de las tres causas comprende **94 clientes distintos** en la base analizada. Es el número de clientes vinculados a una o más condiciones de incidencia; no significa que los 94 tengan un importe de devolución ya determinado.

## Hechos comprobados

### Reintento de facturación

- Jenkins #48 comenzó el 5 de octubre a las 02:00 y terminó con timeout a las 02:45. El proceso 30 permanece `EN_CURSO` y no tiene hora de fin.
- El proceso 30 insertó 61 facturas por 3.913,10 €. A las 08:15, `jlopez` inició el proceso 31, que terminó correctamente con 142 facturas por 8.776,37 €.
- Hay **61 contratos** con dos facturas de septiembre: 122 facturas en esos pares. En **46 contratos** las dos facturas constan como `pagada`.
- Los importes de las copias de esos 46 pares suman **2.956,19 €** en la base. El estado `pagada` no demuestra por sí solo que el banco haya cargado dos recibos; la reclamación del cliente 7 sí declara dos cargos, pero requiere conciliación bancaria.
- El procedimiento inserta factura a factura, sin transacción que abarque toda la ejecución y sin comprobar si ya existen facturas para el periodo. La ejecución parcial quedó disponible para el segundo intento.

### Lecturas repetidas

- Se identificaron **44 grupos / 44 filas sobrantes** de lecturas de septiembre con contrato, periodo, lectura de contador, consumo y tipo idénticos.
- Las filas proceden de `SUR_20261002_01.csv` y `SUR_20261003_01.csv`; los procesos de carga 27 y 29 registran ambos ficheros con 44 filas.
- El procedimiento suma las filas de `lecturas`, por lo que los consumos repetidos inflan el consumo mensual. Para el cliente 119, la lectura de septiembre de 316 kWh aparece dos veces y factura 632 kWh, frente a 313 kWh en agosto.
- No se borran ni modifican las lecturas originales con este paquete. La regularización requiere validar facturas, lecturas y documentos emitidos según el procedimiento contable.

### Precio de `TEMPO_FIJA`

- El precio fue 0,135 €/kWh hasta el 14 de septiembre y 0,149 €/kWh desde el 15.
- Las facturas del periodo guardan 0,149 €/kWh para todo el consumo. El procedimiento seleccionó el precio con `vigente_hasta IS NULL` y lo multiplicó por el total mensual.
- El alcance es de **43 clientes y 44 contratos**, con 69 facturas: 59 figuran pagadas y 10 emitidas. Hay 38 clientes en el grupo pagado y 8 en el emitido; puede haber solapamiento entre estados por las dos ejecuciones.
- No se puede calcular el ajuste exacto con un único consumo mensual: faltan consumos separados para los tramos 1–14 y 15–30 de septiembre y una regla aprobada para redondeo y término fijo. No se propone una devolución por importe estimado.

### Reclamación que necesita contraste

La reclamación del cliente 97 compara 110,29 € en septiembre con importes habituales de 23,15 €. El dato del seed no demuestra que los 745 kWh sean incorrectos. Solicitar y contrastar la lectura/curva de la distribuidora y revisar el detalle de cálculo antes de modificar esa factura.

## Respuesta propuesta

1. Conciliar con el sistema bancario los 46 pares de facturas que constan pagadas. Confirmar qué recibos se presentaron y cobraron antes de acordar devoluciones.
2. Para copias aún emitidas, confirmar cuál es el documento válido con Facturación y anular solo la copia aprobada. `02_correccion.sql` deja una vista previa sin cambios permanentes y ofrece una vía de escritura condicionada: exige introducir ambos IDs y la aprobación, y registra la acción sin borrar la factura. La corrección no se considera aplicada mientras Facturación no autorice y ejecute IDs concretos.
3. Revisar los 44 pares de lecturas con la distribuidora y recalcular los importes a partir de evidencia aceptada. No editar los datos fuente en este ejercicio.
4. Pedir a Facturación/Producto la regla de prorrateo del cambio de precio y los datos de consumo por tramo. Hasta resolverlo, no calcular ni emitir ajustes automáticos para `TEMPO_FIJA`.
5. Revisar individualmente la reclamación 97 con la distribuidora.

## Prevención y ejecución

Desde la raíz del repositorio, con SQL Server de Parte 2 levantado (`docker compose -f parte2/compose.yaml up -d`), ejecutar el diagnóstico y la vista previa con la contraseña de evaluación:

```bash
docker compose -f parte2/compose.yaml exec -T db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Prueba.Tecnica.2026' -C -I -d facturacion < parte2/scripts/01_diagnostico.sql
docker compose -f parte2/compose.yaml exec -T db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Prueba.Tecnica.2026' -C -I -d facturacion < parte2/scripts/02_correccion.sql
```

`02_correccion.sql` muestra los candidatos sin crear tablas permanentes ni modificar datos cuando `@Aplicar = 0`. Es una corrección condicionada, no una reparación ejecutada. Para aplicarla tras aprobación, cargar en `#Aprobaciones` el ID de la copia, el ID que se conserva y la referencia de aprobación; revisar la vista previa y cambiar `@Aplicar` a `1`. Solo acepta copias en estado `emitida`. En modo escritura crea la tabla de auditoría, conserva ambas facturas y evita duplicar el evento al repetir la misma aprobación. Las pagadas requieren conciliación y tratamiento contable fuera de este script.

Revisar `03_prevencion.sql` antes de instalarlo; después de aprobarlo, aplicarlo así:

```bash
docker compose -f parte2/compose.yaml exec -T db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Prueba.Tecnica.2026' -C -I -d facturacion < parte2/scripts/03_prevencion.sql
```

El script instala `dbo.sp_register_reading_once`, que devuelve la fila existente para un reintento idéntico y rechaza con conflicto una lectura distinta para el mismo contrato y periodo. El cargador debe utilizar este procedimiento; un `INSERT` directo puede eludir el control. También sustituye `dbo.sp_facturar_periodo`: serializa ejecuciones, hace la generación atómica y se detiene si ya hay facturas del periodo, detecta lecturas exactas duplicadas o no hay un precio único válido para todo el mes. La prevención de facturación es de cierre seguro: evita facturar datos dudosos, pero no resuelve por sí misma los casos. El cambio de `TEMPO_FIJA` requiere todavía consumos por tramo y una regla aprobada de prorrateo y redondeo. No se deben emitir esas facturas hasta disponer de ambos.

## Verificación realizada en la base de evaluación

- La versión anterior de `01_diagnostico.sql` se ejecutó sin errores y confirmó las 61 parejas duplicadas, las 44 lecturas sobrantes y las 43 personas de `TEMPO_FIJA`. La unión de causas debe verificarse con el nuevo resultado agregado de 94 clientes.
- La versión anterior de `02_correccion.sql` mostró los pares candidatos y no modificó facturas. La versión actual mantiene el preview sin cambios permanentes y limita el DDL a la vía de escritura aprobada.
- La versión anterior de `03_prevencion.sql` se instaló. El procedimiento bloqueó el reintento de septiembre con el error 51012 y el recuento permaneció en 203. La versión actual añade el procedimiento idempotente de ingesta y debe instalarse y comprobarse en la base de evaluación antes de dar por cerrada esa mejora.

## Decisiones pendientes de negocio

- Qué factura conservar en cada contrato duplicado y qué tratamiento dar a documentos ya emitidos.
- Confirmación bancaria de los pares marcados como pagados y, en su caso, autorización y procedimiento de devolución.
- Criterio para resolver lecturas repetidas: prevalencia del fichero, confirmación de distribuidora o regla distinta.
- Prorrateo y redondeo para tarifas con cambios dentro del periodo, incluido el tratamiento del término fijo.
- Resultado de la validación externa del consumo reclamado por el cliente 97.
