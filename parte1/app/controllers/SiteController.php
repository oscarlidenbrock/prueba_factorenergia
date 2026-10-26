<?php

declare(strict_types=1);

namespace app\controllers;

use Yii;
use yii\web\Controller;

final class SiteController extends Controller
{
    public function actionIndex(): array
    {
        $contracts = (int) Yii::$app
            ->db
            ->createCommand('SELECT COUNT(*) FROM dbo.contratos')
            ->queryScalar();

        return [
            'status' => 'ok',
            'database' => 'connected',
            'contracts' => $contracts,
        ];
    }
}