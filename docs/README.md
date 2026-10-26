# Prueba Técnica

## Contexto

La prueba contiene dos ejercicios independientes:

| Carpeta | Ejercicio |
|---------|-----------|
| `parte1/` | Construir una API en PHP para recibir lecturas de contador |
| `parte2/` | Investigar una incidencia en la facturación sobre SQL Server |

Los dos ejercicios se basan en la operativa de una comercializadora de electricidad. No necesitas conocer el sector: lo imprescindible está en el glosario y en el `README.md` de cada parte. Lo que no está explicado forma parte de las decisiones que esperamos que tomes.

## Glosario

- **Contrato:** suministro de electricidad de un cliente. Tiene fecha de alta y, cuando deja de estar vigente, fecha de baja.
- **CUPS:** código que identifica el punto de suministro (la vivienda o el local). No cambia aunque cambie el titular del contrato.
- **Distribuidora:** empresa propietaria de la red y de los contadores. Lee los contadores y nos envía las lecturas.
- **Lectura:** valor acumulado del contador, en kWh, en una fecha. El consumo de un periodo es la diferencia entre dos lecturas.
- **Lectura estimada:** cuando la distribuidora no puede leer el contador, envía un valor estimado. Cuando llega una lectura real, se regulariza la diferencia.

## Qué queremos observar

No buscamos la solución con más código ni la arquitectura más sofisticada. Se permite el uso de herramientas de IA para realizar la prueba. Queremos ver si puedes:

- Entender un problema con información incompleta y tomar decisiones razonables.
- Comprobar los aspectos que consideras más importantes.
- Explicar tus decisiones, limitaciones y siguientes pasos.

## Evaluación

En ambos ejercicios evaluaremos dos aspectos:

- **Funcionalidad:** la solución funciona y cumple las características principales solicitadas. Con un plus en funcionalidades secundarias de valor.
- **Decisiones:** las elecciones de producto, diseño e implementación son razonables y puedes explicarlas.

Los criterios concretos de cada ejercicio aparecen en su `README.md`.

## Uso de IA

**El uso de herramientas de IA está permitido y recomendado.** Puedes utilizar las que emplearías en tu trabajo habitual.

La entrega debe seguir siendo tu responsabilidad: revisa lo generado y asegúrate de poder explicar y modificar cualquier parte. En una entrevista posterior te pediremos explicar decisiones y realizar cambios sobre tu solución.

## Requisitos

- Docker con Docker Compose. Cada parte levanta su propio SQL Server 2022, que necesita unos 2 GB de memoria. No hace falta tener las dos partes levantadas a la vez.
- Mac con chip Apple: la imagen de SQL Server solo existe para x86. Activa en Docker Desktop la opción de usar Rosetta para emular x86/amd64.

## Entrega

Mantén las carpetas proporcionadas e incluye:

- El código y los scripts solicitados en cada ejercicio.
- Las dependencias necesarias (`composer.json` en la parte 1).
- Instrucciones suficientes para ejecutar o reproducir el resultado.

Las instrucciones concretas están en el `README.md` de cada carpeta.
