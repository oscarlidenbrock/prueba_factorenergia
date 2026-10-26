# Prueba técnica para Factorenergia

Este documento recoge manualmente el progreso en las dos partes de la prueba técnica.

## Parte 1: API de recepción de lecturas

### Entorno

- Preparado Docker Compose con PHP 8.3 y SQL Server 2022.
- Añadidos `libonig-dev` y la extensión PHP `mbstring` a `../parte1/app/Dockerfile` para cumplir los requisitos de Yii2.
- Creado `../parte1/app/composer.json` e instaladas las dependencias con Composer.
- Verificados Yii2 2.0.55 y el driver `pdo_sqlsrv` 5.12.0.
- Confirmada la conexión HTTP con SQL Server; el endpoint temporal devolvió los 25 contratos del conjunto de datos.

### API de lecturas

- Implementado `POST /lecturas`, que recibe CUPS, fecha de lectura, valor acumulado en kWh y tipo (`real` o `estimada`).
- La aplicación busca el contrato por CUPS y fecha, contemplando CUPS con contratos sucesivos.
- Se rechazan contratos dados de baja, fechas fuera de vigencia, fechas futuras, valores superiores a la capacidad del contador y tipos no admitidos.
- La fecha de recepción se genera en UTC.
- Se utiliza una transacción serializable y bloqueos al comprobar lecturas existentes.
- Un envío nuevo respondió `201 Created`.
- Un reintento idéntico no generó otra lectura y respondió como duplicado.
- Un valor distinto para el mismo contrato y fecha respondió `409 Conflict`.
- Prueba de diez peticiones simultáneas idénticas: una respondió `201`, nueve respondieron `200` y la base de datos conservó una sola fila.
- Se comprobaron los rechazos de contrato dado de baja, fecha fuera de vigencia, fecha futura, CUPS desconocido, lectura fuera de rango y tipo no admitido.
- Confirmado que las filas iniciales 121 y 137 son duplicados exactos de contrato, fecha, valor y tipo; solo cambia `fecha_recepcion`.
- Se creó `../parte1/SOLUCION.md` con instrucciones, contrato HTTP, decisiones y comprobaciones.
- En la comprobación desde un checkout limpio, `../parte1/app/vendor/` no estaba disponible porque no se versiona. Se añadió `composer install --no-interaction --prefer-dist` antes de iniciar la aplicación y se confirmó el arranque y la petición HTTP.
- Configurado el servidor PHP integrado con cuatro workers para la comprobación local de concurrencia; el servidor integrado se usa solo en desarrollo y pruebas.
- Desactivado `YII_DEBUG` en el entry point para evitar filtrar trazas técnicas en respuestas.
- El JSON malformado devuelve `400` con el formato de error propio de la API; se comprobó que no se exponen detalles internos.
- Repetida la prueba de diez peticiones concurrentes con varios workers: una respondió `201`, nueve respondieron `200` y quedó una fila persistida.
- Alcance de idempotencia: está comprobada para escrituras que pasan por este endpoint. Cualquier otro proceso que escriba directamente en `lecturas` debe aplicar una protección equivalente.

## Parte 2: Incidencia en la facturación

- La Parte 2 no requirió desarrollar otra aplicación PHP: el entregable técnico consiste en consultas y cambios T-SQL, más el informe para Facturación.
- Contrastados con consultas SQL los dos procesos de septiembre, las facturas de ambas ejecuciones, las 44 lecturas repetidas, los precios de tarifa y las reclamaciones.
- Confirmados 61 contratos con facturas duplicadas, 44 grupos de lecturas exactas repetidas y 43 clientes/44 contratos afectados por `TEMPO_FIJA`.
- Preparados `../parte2/scripts/01_diagnostico.sql`, `../parte2/scripts/02_correccion.sql`, `../parte2/scripts/03_prevencion.sql` y `../parte2/INFORME.md` en el paquete de entrega.
- La corrección solo anula copias emitidas con IDs y aprobación explícitos; los registros originales se conservan y las facturas pagadas quedan para conciliación bancaria.
- La prevención sustituye `dbo.sp_facturar_periodo`: serializa ejecuciones por periodo, hace atómica la generación y bloquea la facturación si ya existen facturas, si detecta lecturas exactas duplicadas o si no hay un precio único válido para todo el mes.
- Ejecutados el diagnóstico y la vista previa en la base SQL Server de evaluación. La prevención se instaló y el reintento de septiembre devolvió el bloqueo esperado 51012; el recuento permaneció en 203 facturas antes y después. La vista previa no modificó facturas.
- Se conserva sin cambios el registro histórico 30 (`EN_CURSO`) del timeout. Las regularizaciones de facturas pagadas, lecturas duplicadas y cambio de tarifa quedan sujetas a conciliación y decisiones de negocio.
