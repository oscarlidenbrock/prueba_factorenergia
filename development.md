# Prueba técnica para Factorenergia

Este documento recoge manualmente el progreso en las dos partes de la prueba técnica.

## Parte 1: API de recepción de lecturas

### Entorno y comprobaciones

- Preparado Docker Compose con PHP 8.3 y SQL Server 2022.
- Añadidos `libonig-dev` y la extensión PHP `mbstring` al Dockerfile para cumplir los requisitos de Yii2.
- Creado `app/composer.json` e instalado Yii2 con Composer.
- Verificados Yii2 2.0.55 y el driver `pdo_sqlsrv` 5.12.0.
- Añadidos el arranque HTTP de Yii2 y una ruta temporal para comprobar la conexión con la base de datos.
- Confirmada la conexión con SQL Server y la carga de los 25 contratos de ejemplo.

### API de lecturas

- Implementado `POST /lecturas` para recibir CUPS, fecha, lectura acumulada en kWh y tipo (`real` o `estimada`).
- Validada la vigencia del contrato a partir del CUPS y la fecha de lectura, teniendo en cuenta que un CUPS puede corresponder a contratos sucesivos.
- Rechazados contratos dados de baja y lecturas que superan la capacidad del contador.
- Guardada la fecha de recepción en UTC.
- Comprobado que una lectura nueva responde `201 Created`.
- Comprobado que un reintento idéntico no genera una nueva lectura.
- Comprobado que una lectura diferente para el mismo contrato y fecha responde `409 Conflict`.

### Pendiente

- Revisar el tratamiento de duplicados ya presentes en los datos iniciales y la estrategia de idempotencia frente a escrituras concurrentes.
- Completar las pruebas de validación y documentar el contrato de la API en `parte1/SOLUCION.md`.

## Parte 2: Incidencia en la facturación

Pendiente de investigar la base de datos, el procedimiento almacenado y los logs de Jenkins. Después se prepararán los scripts SQL y el informe solicitado.
