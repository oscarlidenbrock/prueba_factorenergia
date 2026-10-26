# Prueba técnica para Factorenergia

Este documento recoge manualmente el progreso en las dos partes de la prueba técnica.

## Parte 1: API de recepción de lecturas

### Entorno

- Preparado Docker Compose con PHP 8.3 y SQL Server 2022.
- Añadidos `libonig-dev` y la extensión PHP `mbstring` al Dockerfile para cumplir los requisitos de Yii2.
- Creado `app/composer.json` e instaladas las dependencias con Composer.
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
- Se comprobaron los rechazos de contrato dado de baja, fecha fuera de vigencia, fecha futura, CUPS desconocido, lectura fuera de rango y tipo no admitido.
- Se creó `parte1/SOLUCION.md` con instrucciones, contrato HTTP, decisiones y comprobaciones.

### Pendiente

- Revisar el tratamiento de duplicados presentes en los datos iniciales y dejar claramente documentado el alcance de la garantía de idempotencia.
- Revisar si hacen falta comprobaciones adicionales y confirmar que todas las instrucciones de ejecución reproducen el entorno desde una clonación limpia.

## Parte 2: Incidencia en la facturación

Pendiente de investigar la base de datos, el procedimiento almacenado y los logs de Jenkins. Después se prepararán los scripts SQL de diagnóstico, corrección y prevención, junto con el informe para Facturación.
