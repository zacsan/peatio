# encoding: UTF-8
# frozen_string_literal: true



# People exchange commodities in markets. Each market focuses on certain
# commodity pair `{A, B}`. By convention, we call people exchange A for B
# *sellers* who submit *ask* orders, and people exchange B for A *buyers*
# who submit *bid* orders.
#
# ID of market is always in the form "#{B}#{A}". For example, in 'btcusd'
# market, the commodity pair is `{btc, usd}`. Sellers sell out _btc_ for
# _usd_, buyers buy in _btc_ with _usd_. _btc_ is the `base_unit`, while
# _usd_ is the `quote_unit`.
#
# Given market BTCUSD.
# Ask/Base unit = BTC.
# Bid/Quote unit = USD.
#

class Market < ApplicationRecord

  attr_readonly :ask_unit, :bid_unit, :ask_precision, :bid_precision
  delegate :bids, :asks, :trades, :ticker, :h24_volume, :avg_h24_price,
           to: :global

  scope :ordered, -> { order(position: :asc) }
  scope :enabled, -> { where(enabled: true) }
  scope :with_base_unit, -> (base_unit){ where(ask_unit: base_unit) }

  validate { errors.add(:ask_unit, :invalid) if ask_unit == bid_unit }
  validate { errors.add(:id, :taken) if Market.where(ask_unit: bid_unit, bid_unit: ask_unit).present? }
  validates :id, uniqueness: { case_sensitive: false }, presence: true
  validates :ask_unit, :bid_unit, presence: true
  validates :ask_fee, :bid_fee, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 0.5 }
  validates :ask_precision, :bid_precision, :position, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :ask_unit, :bid_unit, inclusion: { in: -> (_) { Currency.codes } }
  validate  :precisions_must_be_same
  validate  :units_must_be_enabled, if: :enabled?

  validates :min_ask_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :max_bid_price, numericality: { allow_blank: true, greater_than_or_equal_to: ->(market){ market.min_ask_price }}

  validates :min_ask_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :min_bid_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_validation(on: :create) { self.id = "#{ask_unit}#{bid_unit}" }

  validate :must_not_disable_all_markets, on: :update

  after_commit { AMQPQueue.enqueue(:matching, action: 'new', market: id) }

  # @deprecated
  def base_unit
    ask_unit
  end

  # @deprecated
  def quote_unit
    bid_unit
  end

  # @deprecated
  def bid
    { fee: bid_fee, currency: bid_unit, fixed: bid_precision }
  end

  # @deprecated
  def ask
    { fee: ask_fee, currency: ask_unit, fixed: ask_precision }
  end

  def name
    "#{ask_unit}/#{bid_unit}".upcase
  end

  def as_json(*)
    super.merge!(name: name)
  end

  alias to_s name

  def latest_price
    Trade.latest_price(self)
  end

  # type is :ask or :bid
  def fix_number_precision(type, d)
    d.round send("#{type}_precision"), BigDecimal::ROUND_DOWN
  end

  def unit_info
    {name: name, base_unit: ask_unit, quote_unit: bid_unit}
  end

  def global
    Global[id]
  end

private

  def precisions_must_be_same
    if ask_precision? && bid_precision? && ask_precision != bid_precision
      errors.add(:ask_precision, :invalid)
      errors.add(:bid_precision, :invalid)
    end
  end

  def units_must_be_enabled
    %i[bid_unit ask_unit].each do |unit|
      errors.add(unit, 'is not enabled.') if Currency.lock.find_by_id(public_send(unit))&.disabled?
    end
  end

  def must_not_disable_all_markets
    if enabled_was && !enabled? && Market.enabled.count == 1
      errors.add(:market, 'is last enabled.')
    end
  end
end

# == Schema Information
# Schema version: 20190116140939
#
# Table name: markets
#
#  id             :string(20)       not null, primary key
#  ask_unit       :string(10)       not null
#  bid_unit       :string(10)       not null
#  ask_fee        :decimal(17, 16)  default(0.0), not null
#  bid_fee        :decimal(17, 16)  default(0.0), not null
#  min_ask_price  :decimal(32, 16)  default(0.0), not null
#  max_bid_price  :decimal(32, 16)  default(0.0), not null
#  min_ask_amount :decimal(32, 16)  default(0.0), not null
#  min_bid_amount :decimal(32, 16)  default(0.0), not null
#  ask_precision  :integer          default(8), not null
#  bid_precision  :integer          default(8), not null
#  position       :integer          default(0), not null
#  enabled        :boolean          default(TRUE), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_markets_on_ask_unit               (ask_unit)
#  index_markets_on_ask_unit_and_bid_unit  (ask_unit,bid_unit) UNIQUE
#  index_markets_on_bid_unit               (bid_unit)
#  index_markets_on_enabled                (enabled)
#  index_markets_on_position               (position)
#
