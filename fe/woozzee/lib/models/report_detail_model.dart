// lib/models/report_detail_model.dart
import 'package:pluto_grid/pluto_grid.dart';
class ReportDetail {
  // Класс не хранит данные, только предоставляет статические методы для метаданных

  // Получить тип данных поля
  static String getFieldDataType(String field) {
    // Определяем типы для полей возвратов
    if (field == 'retail_price_recovery' ||
        field == 'retail_amount_refunded' ||
        field == 'ppvz_for_recovery' ||
        field == 'cost_price_recovered' ||
        field == 'additional_expenses_recovered' ||
        field == 'commission_amount_reversed' ||
        field == 'commission_normal_reversed' ||
        field == 'penalty_commission_reversed' ||
        field == 'return_delivery_rub' ||
        field == 'ppvz_reward_reversed' ||
        field == 'acquiring_fee_reversed' ||
        field == 'cashback_amount_reversed' ||
        field == 'cashback_commission_change_reversed') {
      return 'currency';
    }

    // Даты
    if (field.endsWith('_dt') ||
        field == 'report_date' ||
        field == 'created_at' ||
        field == 'updated_at') {
      return 'date';
    }

    // Проценты
    else if (field.endsWith('_percent') ||
        field.endsWith('_prc') ||
        field.contains('percent') ||
        field.contains('prc')) {
      return 'percent';
    }

    // Валюты
    else if (field.endsWith('_amount') ||
        field.endsWith('_price') ||
        field.endsWith('_rub') ||
        field.endsWith('_fee') ||
        field.endsWith('_commission') ||
        field == 'retail_price' ||
        field == 'retail_amount' ||
        field == 'cost_price' ||
        field == 'additional_expenses' ||
        field == 'commission_amount' ||
        field == 'commission_normal' ||
        field == 'penalty_commission_rub' ||
        field == 'delivery_rub' ||
        field == 'ppvz_reward' ||
        field == 'acquiring_fee' ||
        field == 'acceptance' ||
        field == 'cashback_amount' ||
        field == 'cashback_commission_change' ||
        field == 'storage_fee' ||
        field == 'penalty' ||
        field == 'deduction' ||
        field == 'installment_cofinancing_amount' ||
        field == 'additional_payment' ||
        field == 'payment_schedule') {
      return 'currency';
    }

    // Целые числа
    else if (field == 'quantity' ||
        field == 'delivery_amount' ||
        field == 'return_amount' ||
        field == 'delivery_time_hours' ||
        field == 'nm_id' ||
        field == 'id' ||
        field == 'operation_quantity') {
      return 'integer';
    }

    // Идентификаторы
    else if (field.endsWith('_id') ||
        field == 'srid' ||
        field == 'rrd_id' ||
        field == 'order_uid' ||
        field == 'shk_id' ||
        field == 'sticker_id' ||
        field == 'assembly_id' ||
        field == 'gi_id' ||
        field == 'ppvz_office_id' ||
        field == 'trbx_id' ||
        field == 'seller_promo_id' ||
        field == 'loyalty_id' ||
        field == 'uuid_promocode') {
      return 'id';
    }

    // Текст (по умолчанию)
    else {
      return 'text';
    }
  }

  // Получить список всех имен полей в правильном порядке
  static List<String> getFieldNames() {
    return [
      'id',
      'srid',
      'operation_quantity',
      'shk_id',
      'sticker_id',
      'rrd_id',
      'assembly_id',
      'nm_id',
      'sa_name',
      'barcode',
      'gi_id',
      'ppvz_office_id',
      'order_uid',
      'trbx_id',
      'seller_promo_id',
      'loyalty_id',
      'uuid_promocode',
      'subject_name',
      'brand_name',
      'ts_name',
      'doc_type_name',
      'supplier_oper_name',
      'bonus_type_name',
      'payment_processing',
      'rr_dt',
      'order_dt',
      'sale_dt',
      'delivery_time_hours',
      'type_fb',
      'delivery_method',
      'gi_box_type_name',
      'site_country',
      'office_name',
      'ppvz_office_name',
      'dlv_prc',
      'acquiring_percent',
      'commission_percent',
      'base_comission',
      'penalty_commission_percent',
      'is_kgvp_v2',
      'loyalty_discount',
      'ppvz_kvw_prc',
      'ppvz_kvw_prc_base',
      'ppvz_spp_prc',
      'product_discount_for_report',
      'sale_percent',
      'sale_price_promocode_discount_prc',
      'seller_promo_discount',
      'sup_rating_prc_up',
      'supplier_promo',
      'wibes_wb_discount_percent',
      'quantity',
      'delivery_amount',
      'return_amount',
      'retail_price',
      // Поля возвратов (в правильном порядке)
      'retail_price_recovery',
      'retail_amount',
      'retail_amount_refunded',
      'ppvz_for_pay',
      'ppvz_for_recovery',
      'cost_price',
      'cost_price_recovered',
      'additional_expenses',
      'additional_expenses_recovered',
      'commission_amount',
      'commission_amount_reversed',
      'commission_normal',
      'commission_normal_reversed',
      'penalty_commission_rub',
      'penalty_commission_reversed',
      'delivery_rub',
      'return_delivery_rub',
      'ppvz_reward',
      'ppvz_reward_reversed',
      'acquiring_fee',
      'acquiring_fee_reversed',
      'acceptance',
      'cashback_amount',
      'cashback_amount_reversed',
      'cashback_commission_change',
      'cashback_commission_change_reversed',
      'storage_fee',
      'penalty',
      'deduction',
      'installment_cofinancing_amount',
      'additional_payment',
      'payment_schedule',
      'report_date',
      'created_at',
      'updated_at',
    ];
  }

  // Получить формат отображения для типа данных
  static String getFieldDisplayFormat(String field) {
    final dataType = getFieldDataType(field);

    switch (dataType) {
      case 'currency':
        return '#,##0.00 ₽';
      case 'percent':
        return '#,##0.00%';
      case 'integer':
        return '#,##0';
      case 'date':
        return 'yyyy-MM-dd';
      default:
        return '';
    }
  }

  // Проверить, является ли поле числовым (поддерживает статистику)
  static bool isNumericField(String field) {
    final dataType = getFieldDataType(field);
    return dataType == 'currency' ||
        dataType == 'percent' ||
        dataType == 'integer' ||
        field == 'quantity' ||
        field == 'delivery_amount' ||
        field == 'return_amount';
  }

  // Проверить, является ли поле датой
  static bool isDateField(String field) {
    final dataType = getFieldDataType(field);
    return dataType == 'date';
  }

  // Получить название столбца на русском (можно вынести в отдельный словарь)
  static String getFieldDisplayName(String field) {
    const Map<String, String> translations = {
      'id': 'ID',
      'srid': 'ID заказа',
      'shk_id': 'Штрихкод',
      'sticker_id': 'Стикер',
      'rrd_id': 'Строка',
      'assembly_id': 'Задание',
      'nm_id': 'Артикул WB',
      'sa_name': 'Мой артикул',
      'barcode': 'Баркод',
      'gi_id': 'Номер поставки',
      'ppvz_office_id': 'Офис доставки',
      'order_uid': 'ID транзакции',
      'trbx_id': 'Номер короба',
      'seller_promo_id': 'ID акции продавца',
      'loyalty_id': 'ID скидки лояльности',
      'uuid_promocode': 'ID промокода',
      'subject_name': 'Предмет',
      'brand_name': 'Бренд',
      'ts_name': 'Размер',
      'doc_type_name': 'Тип документа',
      'supplier_oper_name': 'Обоснование',
      'bonus_type_name': 'Виды логистики, штрафов и корректировок ВВ',
      'payment_processing': 'Тип платежа за Эквайринг',
      'rr_dt': 'Дата операции',
      'order_dt': 'Дата заказа',
      'sale_dt': 'Дата продажи',
      'delivery_time_hours': 'Время доставки (в часах)',
      'type_fb': 'Тип FBO/FBS',
      'delivery_method': 'Способ продажи и тип товара',
      'gi_box_type_name': 'Тип коробов',
      'site_country': 'Страна продажи',
      'office_name': 'Склад',
      'ppvz_office_name': 'Наименование офиса доставки',
      'dlv_prc': 'Фиксированный коэффициент склада по поставке',
      'acquiring_percent': 'Размер комиссии за эквайринг/Комиссии за организацию платежей, %',
      'commission_percent': 'Размер кВВ, %',
      'base_comission': 'Базовая комиссия',
      'penalty_commission_percent': 'Штрафная комиссия, %',
      'is_kgvp_v2': 'Размер снижения кВВ из-за акции, %',
      'loyalty_discount': 'Размер скидки лояльности от продавца, %',
      'ppvz_kvw_prc': 'Итоговый кВВ без НДС, %',
      'ppvz_kvw_prc_base': 'Размер кВВ без НДС, % базовый',
      'ppvz_spp_prc': 'Скидка постоянного Покупателя (СПП), %',
      'product_discount_for_report': 'Итоговая согласованная скидка, %',
      'sale_percent': 'Согласованный продуктовый дисконт, %',
      'sale_price_promocode_discount_prc': 'Скидка за промокод, %',
      'seller_promo_discount': 'Размер дополнительной скидки по собственной акции продавца, %',
      'sup_rating_prc_up': 'Размер снижения кВВ из-за рейтинга, %',
      'supplier_promo': 'Промокод, %',
      'wibes_wb_discount_percent': 'Скидка Wibes, %',
      'quantity': 'Количество',
      'delivery_amount': 'Количество доставок',
      'return_amount': 'Количество возврата',
      'retail_price': 'Цена розничная',
      'retail_amount': 'Вайлдберриз реализовал Товар (Пр)',
      'ppvz_for_pay': 'К перечислению продавцу за реализованный товар',
      'cost_price': 'Себестоимость',
      'additional_expenses': 'Доп.расходы',
      'commission_amount': 'Комиссия, руб.',
      'commission_normal': 'Нормальная комиссия',
      'penalty_commission_rub': 'Поздняя отгрузка',
      'delivery_rub': 'Логистика',
      'ppvz_reward': 'Возмещение за выдачу и возврат товаров на ПВЗ',
      'acquiring_fee': 'Эквайринг',
      'acceptance': 'Приемка',
      'cashback_amount': 'Сумма, удержанная за начисленные баллы программы лояльности',
      'cashback_commission_change': 'Стоимость участия в программе лояльности',
      'storage_fee': 'Хранение',
      'penalty': 'Штрафы',
      'deduction': 'Удержания',
      'installment_cofinancing_amount': 'Скидка по программе софинансирования',
      'additional_payment': 'Корректировка Вознаграждения Вайлдберриз (ВВ)',
      'payment_schedule': 'Разовое изменение срока перечисления денежных средств',
      'report_date': 'Дата отчета',
      'retail_price_recovery': 'Цена возврата',
      'retail_amount_refunded': 'Вайлдберриз принял возврат товара',
      'ppvz_for_recovery': 'К снятию с продавца за возвращенный товар',
      'cost_price_recovered': 'Возврат себестоимости',
      'additional_expenses_recovered': 'Возврат доп.расходов',
      'commission_amount_reversed': 'Отмененная комиссия',
      'commission_normal_reversed': 'Отмененная нормальная комиссия',
      'penalty_commission_reversed': 'Отмена корректировки комиссии',
      'return_delivery_rub': 'Стоимость обратной логистики',
      'ppvz_reward_reversed': 'Возврат удержания за ПВЗ',
      'acquiring_fee_reversed': 'Возврат эквайринга',
      'cashback_amount_reversed': 'Отмена удержания за начисленные баллы',
      'cashback_commission_change_reversed': 'Отмена удержания за участие в программе лояльности',
      'created_at': 'Дата создания',
      'updated_at': 'Дата обновления',
      'total': 'Итого',
    };

    return translations[field] ?? field;
  }

  // Получить тип колонки PlutoGrid для поля
  static PlutoColumnType getPlutoColumnType(String field) {
    if (isDateField(field)) {
      return PlutoColumnType.date(format: 'yyyy-MM-dd');
    } else if (isNumericField(field)) {
      return PlutoColumnType.number(format: getFieldDisplayFormat(field));
    } else {
      return PlutoColumnType.text();
    }
  }

  // Получить ширину колонки для поля
  static double getColumnWidth(String field) {
    if (isDateField(field)) {
      return 120;
    } else if (field == 'total') {
      return 100;
    } else if (field.endsWith('_amount') ||
        field.endsWith('_price') ||
        field.endsWith('_rub') ||
        field.endsWith('_fee') ||
        field.endsWith('_commission')) {
      return 150;
    } else if (field == 'sa_name' ||
        field == 'subject_name' ||
        field == 'brand_name' ||
        field == 'supplier_oper_name' ||
        field == 'bonus_type_name') {
      return 200;
    } else if (field == 'srid' ||
        field == 'rrd_id' ||
        field == 'order_uid') {
      return 180;
    } else if (field == 'quantity' ||
        field == 'nm_id' ||
        field == 'id') {
      return 100;
    } else {
      return 150;
    }
  }
}