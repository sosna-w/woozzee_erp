from .db import db
from datetime import datetime

class ReportDetail(db.Model):
    __tablename__ = 'report_details'
    
    id = db.Column(db.Integer, primary_key=True, info={'description_ru': 'ID записи'})
    
    # Основные поля из API
    srid = db.Column(db.String(50), index=True, info={'description_ru': 'Уникальный ID заказа'})
    operation_quantity = db.Column(db.Integer, default=1, info={'description_ru': 'Количество операций по заказу'})
    shk_id = db.Column(db.String(50), info={'description_ru': 'Штрихкод'})
    sticker_id = db.Column(db.String(50), info={'description_ru': 'Цифровое значение стикера'})
    rrd_id = db.Column(db.String(300), unique=True, index=True, info={'description_ru': 'Номер строки'})
    assembly_id = db.Column(db.String(50), info={'description_ru': 'Номер сборочного задания'})
    nm_id = db.Column(db.Integer, index=True, info={'description_ru': 'Артикул WB'})
    sa_name = db.Column(db.String(100), index=True, info={'description_ru': 'Артикул продавца'})
    barcode = db.Column(db.String(50), info={'description_ru': 'Баркод'})
    gi_id = db.Column(db.String(50), info={'description_ru': 'Номер поставки'})
    ppvz_office_id = db.Column(db.String(50), info={'description_ru': 'Номер офиса доставки'})
    order_uid = db.Column(db.String(100), info={'description_ru': 'ID транзакции'})
    trbx_id = db.Column(db.String(50), info={'description_ru': 'Номер короба для обработки товара'})
    seller_promo_id = db.Column(db.String(50), info={'description_ru': 'ID собственной акции продавца с дополнительной скидкой'})
    loyalty_id = db.Column(db.String(50), info={'description_ru': 'ID скидки лояльности от продавца'})
    uuid_promocode = db.Column(db.String(100), info={'description_ru': 'ID промокода'})
    subject_name = db.Column(db.String(200), info={'description_ru': 'Предмет'})
    brand_name = db.Column(db.String(200), info={'description_ru': 'Бренд'})
    ts_name = db.Column(db.String(100), info={'description_ru': 'Размер'})
    doc_type_name = db.Column(db.String(500), info={'description_ru': 'Тип документа'})
    supplier_oper_name = db.Column(db.String(500), info={'description_ru': 'Обоснование для оплата'})
    bonus_type_name = db.Column(db.String(500), info={'description_ru': 'Виды логистики, штрафов и корректировок ВВ'})
    payment_processing = db.Column(db.String(500), info={'description_ru': 'Тип платежа за Эквайринг/Комиссии за организацию платежей'})
    
    # Даты
    rr_dt = db.Column(db.DateTime, info={'description_ru': 'Дата операции'})
    order_dt = db.Column(db.DateTime, info={'description_ru': 'Дата заказа'})
    sale_dt = db.Column(db.DateTime, info={'description_ru': 'Дата продажи'})
    
    # Рассчитанные поля
    delivery_time_hours = db.Column(db.Integer, info={'description_ru': 'Время доставки (в часах)'})
    type_fb = db.Column(db.String(10), info={'description_ru': 'Тип FBO/FBS'})
    delivery_method = db.Column(db.String(100), info={'description_ru': 'Способ продажи и тип товара'})
    gi_box_type_name = db.Column(db.String(100), info={'description_ru': 'Тип коробов'})
    site_country = db.Column(db.String(100), info={'description_ru': 'Страна продажи'})
    office_name = db.Column(db.String(200), info={'description_ru': 'Склад'})
    ppvz_office_name = db.Column(db.String(200), info={'description_ru': 'Наименование офиса доставки'})
    
    # Проценты и коэффициенты
    dlv_prc = db.Column(db.Float, info={'description_ru': 'Фиксированный коэффициент склада по поставке'})
    acquiring_percent = db.Column(db.Float, info={'description_ru': 'Размер комиссии за эквайринг/Комиссии за организацию платежей, %'})
    commission_percent = db.Column(db.Float, info={'description_ru': 'Размер кВВ, %'})
    base_comission = db.Column(db.Float, info={'description_ru': 'Базовая комиссия'})
    penalty_commission_percent = db.Column(db.Float, info={'description_ru': 'Штрафная комиссия, %'})
    is_kgvp_v2 = db.Column(db.Float, info={'description_ru': 'Размер снижения кВВ из-за акции, %'})
    loyalty_discount = db.Column(db.Float, info={'description_ru': 'Размер скидки лояльности от продавца, %'})
    ppvz_kvw_prc = db.Column(db.Float, info={'description_ru': 'Итоговый кВВ без НДС, %'})
    ppvz_kvw_prc_base = db.Column(db.Float, info={'description_ru': 'Размер кВВ без НДС, % базовый'})
    ppvz_spp_prc = db.Column(db.Float, info={'description_ru': 'Скидка постоянного Покупателя (СПП), %'})
    product_discount_for_report = db.Column(db.Float, info={'description_ru': 'Итоговая согласованная скидка, %'})
    sale_percent = db.Column(db.Float, info={'description_ru': 'Согласованный продуктовый дисконт, %'})
    sale_price_promocode_discount_prc = db.Column(db.Float, info={'description_ru': 'Скидка за промокод, %'})
    seller_promo_discount = db.Column(db.Float, info={'description_ru': 'Размер дополнительной скидки по собственной акции продавца, %'})
    sup_rating_prc_up = db.Column(db.Float, info={'description_ru': 'Размер снижения кВВ из-за рейтинга, %'})
    supplier_promo = db.Column(db.Float, info={'description_ru': 'Промокод, %'})
    wibes_wb_discount_percent = db.Column(db.Float, info={'description_ru': 'Скидка Wibes, %'})
    
    # Количественные показатели
    quantity = db.Column(db.Integer, info={'description_ru': 'Количество'})
    delivery_amount = db.Column(db.Integer, info={'description_ru': 'Количество доставок'})
    return_amount = db.Column(db.Integer, info={'description_ru': 'Количество возврата'})
    
    # Родительские и новые столбцы для возвратов
    retail_price = db.Column(db.Float, info={'description_ru': 'Цена розничная'})
    retail_price_recovery = db.Column(db.Float, info={'description_ru': 'Цена возврата'})  # 1.1. Цена возврата
    
    retail_amount = db.Column(db.Float, info={'description_ru': 'Вайлдберриз реализовал Товар (Пр)'})
    retail_amount_refunded = db.Column(db.Float, info={'description_ru': 'Вайлдберриз принял возврат товара'})  # 2.1. Вайлдберриз принял возврат товара
    
    ppvz_for_pay = db.Column(db.Float, info={'description_ru': 'К перечислению продавцу за реализованный товар'})
    ppvz_for_recovery = db.Column(db.Float, info={'description_ru': 'К снятию с продавца за возвращенный товар'})  # 3.1. К снятию с продавца за возвращенный товар
    
    # Себестоимость и расходы
    cost_price = db.Column(db.Float, info={'description_ru': 'Себестоимость'})
    cost_price_recovered = db.Column(db.Float, info={'description_ru': 'Возврат себестоимости'})  # 4.1. Возврат себестоимости
    
    additional_expenses = db.Column(db.Float, info={'description_ru': 'Доп.расходы'})
    additional_expenses_recovered = db.Column(db.Float, info={'description_ru': 'Возврат доп.расходов'})  # 5.1. Возврат доп.расходов
    
    # Комиссии и платежи
    commission_amount = db.Column(db.Float, info={'description_ru': 'Комиссия, руб.'})
    commission_amount_reversed = db.Column(db.Float, info={'description_ru': 'Отмененная комиссия'})  # 6.1. Отмененная комиссия
    
    commission_normal = db.Column(db.Float, info={'description_ru': 'Нормальная комиссия'})
    commission_normal_reversed = db.Column(db.Float, info={'description_ru': 'Отмененная нормальная комиссия'})  # 7.1. Отмененная нормальная комиссия
    
    penalty_commission_rub = db.Column(db.Float, info={'description_ru': 'Переплата в рублях'})
    penalty_commission_reversed = db.Column(db.Float, info={'description_ru': 'Отмена корректировки комиссии'})  # 8.1. Отмена корректировки комиссии
    
    delivery_rub = db.Column(db.Float, info={'description_ru': 'Услуги по доставке товара покупателю'})
    return_delivery_rub = db.Column(db.Float, info={'description_ru': 'Стоимость обратной логистики'})  # 13.1. Стоимость обратной логистики

    ppvz_reward = db.Column(db.Float, info={'description_ru': 'Возмещение за выдачу и возврат товаров на ПВЗ'})
    ppvz_reward_reversed = db.Column(db.Float, info={'description_ru': 'Возврат удержания за ПВЗ'})  # 9.1. Возврат удержания за ПВЗ
    
    acquiring_fee = db.Column(db.Float, info={'description_ru': 'Эквайринг/Комиссии за организацию платежей'})
    acquiring_fee_reversed = db.Column(db.Float, info={'description_ru': 'Возврат эквайринга'})  # 10.1. Возврат эквайринга
    
    acceptance = db.Column(db.Float, info={'description_ru': 'Операции на приёмке'})
    cashback_amount = db.Column(db.Float, info={'description_ru': 'Сумма, удержанная за начисленные баллы программы лояльности'})
    cashback_amount_reversed = db.Column(db.Float, info={'description_ru': 'Отмена удержания за начисленные баллы'})  # 11.1. Отмена удержания за начисленные баллы
    
    cashback_commission_change = db.Column(db.Float, info={'description_ru': 'Стоимость участия в программе лояльности'})
    cashback_commission_change_reversed = db.Column(db.Float, info={'description_ru': 'Отмена удержания за участие в программе лояльности'})  # 12.1. Отмена удержания за участие в программе лояльности
    
    storage_fee = db.Column(db.Float, info={'description_ru': 'Хранение'})
    penalty = db.Column(db.Float, info={'description_ru': 'Общая сумма штрафов'})
    deduction = db.Column(db.Float, info={'description_ru': 'Удержания'})
    installment_cofinancing_amount = db.Column(db.Float, info={'description_ru': 'Скидка по программе софинансирования'})
    additional_payment = db.Column(db.Float, info={'description_ru': 'Корректировка Вознаграждения Вайлдберриз (ВВ)'})
    payment_schedule = db.Column(db.Float, info={'description_ru': 'Разовое изменение срока перечисления денежных средств'})
    
    # Метаданные
    report_date = db.Column(db.Date, nullable=False, index=True, info={'description_ru': 'Дата отчета'})
    created_at = db.Column(db.DateTime, default=datetime.utcnow, info={'description_ru': 'Дата создания записи'})
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, info={'description_ru': 'Дата обновления записи'})

    def to_dict(self):
        """Возвращает словарь с сохранением порядка полей, как в модели"""
        result = {
            'id': self.id,
            'srid': self.srid,
            'operation_quantity': self.operation_quantity,
            'shk_id': self.shk_id,
            'sticker_id': self.sticker_id,
            'rrd_id': self.rrd_id,
            'assembly_id': self.assembly_id,
            'nm_id': self.nm_id,
            'sa_name': self.sa_name,
            'barcode': self.barcode,
            'gi_id': self.gi_id,
            'ppvz_office_id': self.ppvz_office_id,
            'order_uid': self.order_uid,
            'trbx_id': self.trbx_id,
            'seller_promo_id': self.seller_promo_id,
            'loyalty_id': self.loyalty_id,
            'uuid_promocode': self.uuid_promocode,
            'subject_name': self.subject_name,
            'brand_name': self.brand_name,
            'ts_name': self.ts_name,
            'doc_type_name': self.doc_type_name,
            'supplier_oper_name': self.supplier_oper_name,
            'bonus_type_name': self.bonus_type_name,
            'payment_processing': self.payment_processing,
            'rr_dt': self.rr_dt.isoformat() if self.rr_dt else None,
            'order_dt': self.order_dt.isoformat() if self.order_dt else None,
            'sale_dt': self.sale_dt.isoformat() if self.sale_dt else None,
            'delivery_time_hours': self.delivery_time_hours,
            'type_fb': self.type_fb,
            'delivery_method': self.delivery_method,
            'gi_box_type_name': self.gi_box_type_name,
            'site_country': self.site_country,
            'office_name': self.office_name,
            'ppvz_office_name': self.ppvz_office_name,
            'dlv_prc': self.dlv_prc,
            'acquiring_percent': self.acquiring_percent,
            'commission_percent': self.commission_percent,
            'base_comission': self.base_comission,
            'penalty_commission_percent': self.penalty_commission_percent,
            'is_kgvp_v2': self.is_kgvp_v2,
            'loyalty_discount': self.loyalty_discount,
            'ppvz_kvw_prc': self.ppvz_kvw_prc,
            'ppvz_kvw_prc_base': self.ppvz_kvw_prc_base,
            'ppvz_spp_prc': self.ppvz_spp_prc,
            'product_discount_for_report': self.product_discount_for_report,
            'sale_percent': self.sale_percent,
            'sale_price_promocode_discount_prc': self.sale_price_promocode_discount_prc,
            'seller_promo_discount': self.seller_promo_discount,
            'sup_rating_prc_up': self.sup_rating_prc_up,
            'supplier_promo': self.supplier_promo,
            'wibes_wb_discount_percent': self.wibes_wb_discount_percent,
            'quantity': self.quantity,
            'delivery_amount': self.delivery_amount,
            'return_amount': self.return_amount,
            
            # Новые столбцы для возвратов
            'retail_price': self.retail_price,
            'retail_price_recovery': self.retail_price_recovery,
            'retail_amount': self.retail_amount,
            'retail_amount_refunded': self.retail_amount_refunded,
            'ppvz_for_pay': self.ppvz_for_pay,
            'ppvz_for_recovery': self.ppvz_for_recovery,
            'cost_price': self.cost_price,
            'cost_price_recovered': self.cost_price_recovered,
            'additional_expenses': self.additional_expenses,
            'additional_expenses_recovered': self.additional_expenses_recovered,
            'commission_amount': self.commission_amount,
            'commission_amount_reversed': self.commission_amount_reversed,
            'commission_normal': self.commission_normal,
            'commission_normal_reversed': self.commission_normal_reversed,
            'penalty_commission_rub': self.penalty_commission_rub,
            'penalty_commission_reversed': self.penalty_commission_reversed,
            'delivery_rub': self.delivery_rub,
            'return_delivery_rub': self.return_delivery_rub,
            'ppvz_reward': self.ppvz_reward,
            'ppvz_reward_reversed': self.ppvz_reward_reversed,
            'acquiring_fee': self.acquiring_fee,
            'acquiring_fee_reversed': self.acquiring_fee_reversed,
            'acceptance': self.acceptance,
            'cashback_amount': self.cashback_amount,
            'cashback_amount_reversed': self.cashback_amount_reversed,
            'cashback_commission_change': self.cashback_commission_change,
            'cashback_commission_change_reversed': self.cashback_commission_change_reversed,
            'storage_fee': self.storage_fee,
            'penalty': self.penalty,
            'deduction': self.deduction,
            'installment_cofinancing_amount': self.installment_cofinancing_amount,
            'additional_payment': self.additional_payment,
            'payment_schedule': self.payment_schedule,
            'report_date': self.report_date.isoformat() if self.report_date else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
        return result