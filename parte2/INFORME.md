# Informe de incidencia de facturación — septiembre de 2026

## Resumen para Facturación

La facturación de septiembre se ejecutó dos veces después de que Jenkins agotara el tiempo de espera a los 45 minutos. El procedimiento no protegía el periodo frente a reintentos y dejaba las facturas ya insertadas aunque la ejecución no terminara. Además, se cargaron dos veces 44 lecturas de la distribuidora y el procedimiento aplicó a todo el mes el precio de `TEMPO_FIJA` vigente al ejecutar.

Hay tres incidencias confirmadas y una reclamación que requiere comprobación externa. Las cantidades de clientes por causa se solapan, por lo que no deben sumarse como afectados únicos.

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
2. Para copias aún emitidas, confirmar cuál es el documento válido con Facturación y anular solo la copia aprobada. `02_correccion.sql` deja vista previa y exige introducir ambos IDs y la aprobación; registra la acción sin borrar la factura.
3. Revisar los 44 pares de lecturas con la distribuidora y recalcular los importes a partir de evidencia aceptada. No editar los datos fuente en este ejercicio.
4. Pedir a Facturación/Producto la regla de prorrateo del cambio de precio y los datos de consumo por tramo. Hasta resolverlo, no calcular ni emitir ajustes automáticos para `TEMPO_FIJA`.
5. Revisar individualmente la reclamación 97 con la distribuidora.

## Prevención y ejecución

Desde la raíz del repositorio, con SQL Server de Parte 2 levantado (`docker compose -f parte2/compose.yaml up -d`), ejecutar el diagnóstico y la vista previa con la contraseña de evaluación:

```bash
docker compose -f parte2/compose.yaml exec -T db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Prueba.Tecnica.2026' -C -I -d facturacion < parte2/scripts/01_diagnostico.sql
docker compose -f parte2/compose.yaml exec -T db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Prueba.Tecnica.2026' -C -I -d facturacion < parte2/scripts/02_correccion.sql
```

`02_correccion.sql` crea una tabla de auditoría si todavía no existe, muestra todos los candidatos y no modifica facturas mientras `@Aplicar = 0`. Para aplicar una anulación aprobada, añadir a `@Aprobaciones` el ID de la copia, el ID que se conserva y la referencia de aprobación; revisar el preview y cambiar `@Aplicar` a `1`. Solo acepta copias en estado `emitida`. Las pagadas quedan fuera de la operación y requieren conciliación y tratamiento contable. Reejecutarlo con la misma aprobación no duplica la auditoría.

Revisar `03_prevencion.sql` antes de instalarlo; después de aprobarlo, aplicarlo así:

```bash
docker compose -f parte2/compose.yaml exec -T db /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Prueba.Tecnica.2026' -C -I -d facturacion < parte2/scripts/03_prevencion.sql
```

La nueva versión del procedimiento bloquea reintentos si ya hay facturas del periodo, serializa ejecuciones del mismo periodo, mantiene bloqueadas las lecturas mientras factura, hace la generación atómica y se detiene ante lecturas exactas duplicadas o un precio que no cubra unívocamente todo el mes. Las ejecuciones de facturación deben pasar por este procedimiento para compartir esos controles. La parada es deliberada: requiere conciliación de datos antes de facturar. El control de carga debe guardar el fichero/lote procesado y evitar importar de nuevo la misma lectura; el ejercicio no proporciona un proceso de importación que se pueda adaptar aquí.

## Verificación realizada en la base de evaluación

- `01_diagnostico.sql` se ejecutó sin errores y devolvió las ejecuciones, las facturas duplicadas, las 44 lecturas repetidas, el precio aplicado y las reclamaciones.
- `02_correccion.sql` mostró los pares candidatos y terminó indicando que no se modificaron facturas.
- `03_prevencion.sql` se instaló y mostró el registro histórico del proceso 30 en estado `EN_CURSO`.
- Se volvió a invocar el procedimiento para septiembre. Devolvió el bloqueo controlado 51012 porque ya existen facturas; el recuento fue 203 antes y después. No se añadieron facturas.

## Decisiones pendientes de negocio

- Qué factura conservar en cada contrato duplicado y qué tratamiento dar a documentos ya emitidos.
- Confirmación bancaria de los pares marcados como pagados y, en su caso, autorización y procedimiento de devolución.
- Criterio para resolver lecturas repetidas: prevalencia del fichero, confirmación de distribuidora o regla distinta.
- Prorrateo y redondeo para tarifas con cambios dentro del periodo, incluido el tratamiento del término fijo.
- Resultado de la validación externa del consumo reclamado por el cliente 97.
