<?php

declare(strict_types=1);

return [
    'id' => 'lecturas-api',
    'basePath' => dirname(__DIR__),
    'components' => [
        'request' => [
            'cookieValidationKey' => 'clave-local-de-desarrollo',
            'parsers' => [
                'application/json' => yii\web\JsonParser::class,
            ],
        ],
        'response' => [
            'format' => yii\web\Response::FORMAT_JSON,
        ],
        'db' => [
            'class' => yii\db\Connection::class,
            'dsn' => 'sqlsrv:Server=db,1433;Database=lecturas;TrustServerCertificate=1',
            'username' => 'sa',
            'password' => 'Prueba.Tecnica.2026',
            'charset' => 'UTF-8',
        ],
        'urlManager' => [
            'enablePrettyUrl' => true,
            'showScriptName' => false,
            'enableStrictParsing' => false,
            'rules' => [
                [
                    'pattern' => 'lecturas',
                    'route' => 'lectura/create',
                    'verb' => ['POST'],
                ],
            ],
        ],
    ],
];
