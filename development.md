# Prueba técnica para Factorenergia

Este documento recoge manualmente el progreso en las dos partes de la prueba técnica.

## Parte 1: API de recepción de lecturas

### Entorno y comprobación inicial

- Revisada la estructura proporcionada: `compose.yaml`, `app/Dockerfile` y `db/init.sql`.
- Preparado Docker Compose con PHP 8.3 y SQL Server 2022.
- Añadidos `libonig-dev` y la extensión PHP `mbstring` al Dockerfile para cumplir los requisitos de Yii2.
- Creado `app/composer.json` e instalado Yii2 con Composer.
- Verificados Yii2 2.0.55 y el driver `pdo_sqlsrv` 5.12.0.
- Añadidos el arranque HTTP de Yii2 y un endpoint temporal para comprobar la conexión a la base de datos.
- Confirmada la respuesta `200 OK` en `http://localhost:8000/`, con la base de datos conectada y 25 contratos.

### Pendiente

- Implementar `POST /lecturas`.
- Validar los datos recibidos y la vigencia del contrato.
- Resolver los contratos por CUPS y fecha de lectura.
- Evitar duplicados cuando la distribuidora reintente una petición.
- Probar los casos principales y documentar las decisiones de la API.

## Parte 2: Incidencia en la facturación

Pendiente de investigar la base de datos, el procedimiento almacenado y los logs de Jenkins. Después se prepararán los scripts SQL y el informe solicitado.
