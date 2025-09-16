//+------------------------------------------------------------------+
//|                                                    Stop-Out Line |
//|                                      Copyright © 2025, EarnForex |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+
#property copyright "www.EarnForex.com, 2025"
#property link      "https://www.earnforex.com/indicators/Stop-Out-Line/"
#property version   "1.01"
#property strict
#property indicator_chart_window

#property description "Displays a stop-out line for the current symbol."
#property description "You can hide/show the line by pressing Shift+S."

input int      UpdateFrequencyMs = 100;      // Update frequency (milliseconds)
input color    LineColor = clrRed;           // Stop-out line color
input int      LineWidth = 2;                // Stop-out line width
input ENUM_LINE_STYLE LineStyle = STYLE_SOLID; // Stop-out line style
input bool     ShowLabel = true;             // Show price label
input string   LineLabel = "STOP-OUT: ";     // Line label prefix

// Global variables:
string LineObjectName = "StopOutPriceLine";
string LabelObjectName = "StopOutPriceLabel";
double StopOutPrice = 0;

void OnInit()
{
    CalculateStopOutPrice();
    EventSetMillisecondTimer(UpdateFrequencyMs);
}

void OnDeinit(const int reason)
{
    DeleteLineAndLabel();
    EventKillTimer();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    CalculateStopOutPrice();

    return rates_total;
}

void OnTimer()
{
    CalculateStopOutPrice();
}

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    // Update label position on chart change/scroll:
    if (id == CHARTEVENT_CHART_CHANGE)
    {
        UpdateLabelPosition();
    }
    else if (id == CHARTEVENT_KEYDOWN)
    {
        // Trade direction:
        if ((lparam == 'S') && (TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT) < 0))
        {
            if (ObjectGetInteger(0, LineObjectName, OBJPROP_TIMEFRAMES) == OBJ_NO_PERIODS) // Was hidden.
            {
                ObjectSetInteger(0, LineObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
                ObjectSetInteger(0, LabelObjectName, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
            }
            else // Was visible.
            {
                ObjectSetInteger(0, LineObjectName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
                ObjectSetInteger(0, LabelObjectName, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
            }
        }
    }
}

// Calculate stop-out price based on current positions.
void CalculateStopOutPrice()
{
    // Get account parameters.
    double equity = AccountEquity();
    double margin = AccountMargin();
    double stopOutLevel = AccountStopoutLevel(); // Broker's stop-out level in %.
    int stopOutMode = AccountStopoutMode();

    // Check if there are open positions.
    if (margin == 0)
    {
        // No positions, remove the line.
        DeleteLineAndLabel();
        return;
    }

    // Calculate total position parameters for current symbol.
    int positionDirection = 0; // 1 for net long, -1 for net short.
    double netLots = 0;

    // Scan all orders.
    for (int i = 0; i < OrdersTotal(); i++)
    {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
        {
            if (OrderType() <= OP_SELL) // Only market orders
            {
                // Check if order is for current symbol
                if (OrderSymbol() == Symbol())
                {
                    if (OrderType() == OP_BUY)
                    {
                        netLots += OrderLots();
                    }
                    else if (OrderType() == OP_SELL)
                    {
                        netLots -= OrderLots();
                    }
                }
            }
        }
    }

    // Determine position direction.
    if (netLots > 0) positionDirection = 1;  // Net long.
    else if (netLots < 0) positionDirection = -1;  // Net short.
    else
    {
        // No positions, remove the line.
        DeleteLineAndLabel();
        return;
    }

    double symbolPositionLots = MathAbs(netLots);

    // Calculate equity at stop-out.
    double equityAtStopOut;
    if (stopOutMode == 0)
    {
        // Stop-out level is a percentage of margin.
        equityAtStopOut = (stopOutLevel / 100.0) * margin;
    }
    else // 1
    {
        // Stop-out level is a free margin value in account currency.
        equityAtStopOut = equity - (AccountFreeMargin() - stopOutLevel);
    }

    // Calculate maximum loss allowed.
    double maxLoss = equity - equityAtStopOut;

    // Get current price.
    double currentPrice;
    if (positionDirection == 1) currentPrice = Bid; // Net long position is closed at Bid.
    else currentPrice = Ask; // Net short position is closed at Ask.

    // Calculate pip value for the position.
    AccCurrency = AccountCurrency();
    double point_value_risk = CalculatePointValue(Symbol(), Risk);
    if (point_value_risk == 0) return; // No symbol information yet.

    // Calculate price movement needed to reach stop-out.
    double priceMovement = maxLoss / (point_value_risk * MathAbs(netLots));

    // Calculate stop-out price based on position direction.
    if (positionDirection == 1) // Long position.
    {
        StopOutPrice = currentPrice - priceMovement;
    }
    else if (positionDirection == -1) // Short position.
    {
        double spread = Ask - Bid;
        StopOutPrice = currentPrice + priceMovement - spread; // Sell positions are closed at Ask, so the stop-out will happen when the current price goes to the Bid of the expected stop-out price. Hence, the stop-out line should be drawn at that Bid level.
    }

    // Ensure price is normalized.
    StopOutPrice = NormalizeDouble(StopOutPrice, (int)MarketInfo(Symbol(), MODE_DIGITS));

    // Draw or update the horizontal line.
    DrawStopOutLine();
}

// Draw stop-out line on chart.
void DrawStopOutLine()
{
    if (StopOutPrice <= 0) return;

    // Create or move horizontal line.
    if (ObjectFind(ChartID(), LineObjectName) < 0)
    {
        // Create new line.
        ObjectCreate(ChartID(), LineObjectName, OBJ_HLINE, 0, 0, StopOutPrice);
        ObjectSetInteger(ChartID(), LineObjectName, OBJPROP_COLOR, LineColor);
        ObjectSetInteger(ChartID(), LineObjectName, OBJPROP_WIDTH, LineWidth);
        ObjectSetInteger(ChartID(), LineObjectName, OBJPROP_STYLE, LineStyle);
        ObjectSetInteger(ChartID(), LineObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(ChartID(), LineObjectName, OBJPROP_SELECTED, false);
    }
    else
    {
        // Update existing line.
        ObjectSetDouble(ChartID(), LineObjectName, OBJPROP_PRICE, StopOutPrice);
    }

    // Add or update label if enabled.
    if (ShowLabel) UpdateLabelPosition();
}

// Update label position to stay on the left side of visible chart.
void UpdateLabelPosition()
{
    if (StopOutPrice <= 0 || !ShowLabel || Bars == 0) return;

    string labelText = LineLabel + DoubleToString(StopOutPrice, (int)MarketInfo(Symbol(), MODE_DIGITS));

    // Get the leftmost visible bar.
    int firstVisibleBar = (int)ChartGetInteger(ChartID(), CHART_FIRST_VISIBLE_BAR);

    int labelBar = firstVisibleBar;
    if (labelBar < 0) labelBar = 0;

    // Get the time for this bar.
    datetime labelTime = Time[labelBar];

    if (ObjectFind(ChartID(), LabelObjectName) < 0)
    {
        // Create new label.
        ObjectCreate(ChartID(), LabelObjectName, OBJ_TEXT, 0, labelTime, StopOutPrice);
        ObjectSetInteger(ChartID(), LabelObjectName, OBJPROP_COLOR, LineColor);
        ObjectSetInteger(ChartID(), LabelObjectName, OBJPROP_FONTSIZE, 9);
        ObjectSetInteger(ChartID(), LabelObjectName, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
        ObjectSetInteger(ChartID(), LabelObjectName, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(ChartID(), LabelObjectName, OBJPROP_SELECTED, false);
        ObjectSetInteger(ChartID(), LabelObjectName, OBJPROP_BACK, false);
    }
    else
    {
        // Update existing label.
        ObjectSetDouble(ChartID(), LabelObjectName, OBJPROP_PRICE1, StopOutPrice);
        ObjectSetInteger(ChartID(), LabelObjectName, OBJPROP_TIME1, labelTime);
    }

    ObjectSetString(ChartID(), LabelObjectName, OBJPROP_TEXT, labelText);
}

void DeleteLineAndLabel()
{
    ObjectDelete(ChartID(), LineObjectName);
    ObjectDelete(ChartID(), LabelObjectName);
    StopOutPrice = 0;
}

enum mode_of_operation
{
    Risk,
    Reward
};

string AccCurrency;
double CalculatePointValue(string cp, mode_of_operation mode)
{
    double UnitCost;

    int ProfitCalcMode = (int)MarketInfo(cp, MODE_PROFITCALCMODE);
    string ProfitCurrency = SymbolInfoString(cp, SYMBOL_CURRENCY_PROFIT);
    
    if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";
    // If Symbol is CFD or futures but with different profit currency.
    if ((ProfitCalcMode == 1) || ((ProfitCalcMode == 2) && ((ProfitCurrency != AccCurrency))))
    {
        if (ProfitCalcMode == 2) UnitCost = MarketInfo(cp, MODE_TICKVALUE); // Futures, but will still have to be adjusted by CCC.
        else UnitCost = SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_SIZE) * SymbolInfoDouble(cp, SYMBOL_TRADE_CONTRACT_SIZE); // Apparently, it is more accurate than taking TICKVALUE directly in some cases.
        // If profit currency is different from account currency.
        if (ProfitCurrency != AccCurrency)
        {
            double CCC = CalculateAdjustment(ProfitCurrency, mode); // Valid only for loss calculation.
            // Adjust the unit cost.
            UnitCost *= CCC;
        }
    }
    else UnitCost = MarketInfo(cp, MODE_TICKVALUE); // Futures or Forex.
    double OnePoint = MarketInfo(cp, MODE_POINT);

    if (OnePoint != 0) return(UnitCost / OnePoint);
    return UnitCost; // Only in case of an error with MODE_POINT retrieval.
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when ProfitCurrency != AccountCurrency.|
//| ReferenceSymbol changes every time because each symbol has its own RS.            |
//+-----------------------------------------------------------------------------------+
#define FOREX_SYMBOLS_ONLY 0
#define NONFOREX_SYMBOLS_ONLY 1
double CalculateAdjustment(const string profit_currency, const mode_of_operation calc_mode)
{
    string ref_symbol = NULL, add_ref_symbol = NULL;
    bool ref_mode = false, add_ref_mode = false;
    double add_coefficient = 1; // Might be necessary for correction coefficient calculation if two pairs are used for profit currency to account currency conversion. This is handled differently in MT5 version.

    if (ref_symbol == NULL) // Either first run or non-current symbol.
    {
        ref_symbol = GetSymbolByCurrencies(profit_currency, AccCurrency, FOREX_SYMBOLS_ONLY);
        if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(profit_currency, AccCurrency, NONFOREX_SYMBOLS_ONLY);
        ref_mode = true;
        // Failed.
        if (ref_symbol == NULL)
        {
            // Reversing currencies.
            ref_symbol = GetSymbolByCurrencies(AccCurrency, profit_currency, FOREX_SYMBOLS_ONLY);
            if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(AccCurrency, profit_currency, NONFOREX_SYMBOLS_ONLY);
            ref_mode = false;
        }
        if (ref_symbol == NULL)
        {
            if ((!FindDoubleReferenceSymbol("USD", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // USD should work in 99.9% of cases.
             && (!FindDoubleReferenceSymbol("EUR", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // For very rare cases.
             && (!FindDoubleReferenceSymbol("GBP", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))  // For extremely rare cases.
             && (!FindDoubleReferenceSymbol("JPY", profit_currency, ref_symbol, ref_mode, add_ref_symbol, add_ref_mode))) // For extremely rare cases.
            {
                Print("Adjustment calculation critical failure. Failed both simple and two-pair conversion methods.");
                return 1;
            }
        }
    }
    if (add_ref_symbol != NULL) // If two reference pairs are used.
    {
        // Calculate just the additional symbol's coefficient and then use it in final return's multiplication.
        MqlTick tick;
        SymbolInfoTick(add_ref_symbol, tick);
        add_coefficient = GetCurrencyCorrectionCoefficient(tick, calc_mode, add_ref_mode);
    }
    MqlTick tick;
    SymbolInfoTick(ref_symbol, tick);
    return GetCurrencyCorrectionCoefficient(tick, calc_mode, ref_mode) * add_coefficient;
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(const string base_currency, const string profit_currency, const uint symbol_type)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);
        string b_cur;

        // Normal case - Forex pairs:
        if (MarketInfo(symbolname, MODE_PROFITCALCMODE) == 0)
        {
            if (symbol_type == NONFOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
            // Get its base currency.
            b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        }
        else // Weird case for brokers that set conversion pairs as CFDs.
        {
            if (symbol_type == FOREX_SYMBOLS_ONLY) continue; // Avoid checking symbols of a wrong type.
            // Get its base currency as the initial three letters - prone to huge errors!
            b_cur = StringSubstr(symbolname, 0, 3);
        }

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);

        // If the currency pair matches both currencies, select it in Market Watch and return its name.
        if ((b_cur == base_currency) && (p_cur == profit_currency))
        {
            // Select if necessary.
            if (!(bool)SymbolInfoInteger(symbolname, SYMBOL_SELECT)) SymbolSelect(symbolname, true);

            return symbolname;
        }
    }
    return NULL;
}

//+----------------------------------------------------------------------------+
//| Finds reference symbols using 2-pair method.                               |
//| Results are returned via reference parameters.                             |
//| Returns true if found the pairs, false otherwise.                          |
//+----------------------------------------------------------------------------+
bool FindDoubleReferenceSymbol(const string cross_currency, const string profit_currency, string &ref_symbol, bool &ref_mode, string &add_ref_symbol, bool &add_ref_mode)
{
    // A hypothetical example for better understanding:
    // The trader buys CAD/CHF.
    // account_currency is known = SEK.
    // cross_currency = USD.
    // profit_currency = CHF.
    // I.e., we have to buy dollars with francs (using the Ask price) and then sell those for SEKs (using the Bid price).

    ref_symbol = GetSymbolByCurrencies(cross_currency, AccCurrency, FOREX_SYMBOLS_ONLY); 
    if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(cross_currency, AccCurrency, NONFOREX_SYMBOLS_ONLY);
    ref_mode = true; // If found, we've got USD/SEK.

    // Failed.
    if (ref_symbol == NULL)
    {
        // Reversing currencies.
        ref_symbol = GetSymbolByCurrencies(AccCurrency, cross_currency, FOREX_SYMBOLS_ONLY);
        if (ref_symbol == NULL) ref_symbol = GetSymbolByCurrencies(AccCurrency, cross_currency, NONFOREX_SYMBOLS_ONLY);
        ref_mode = false; // If found, we've got SEK/USD.
    }
    if (ref_symbol == NULL)
    {
        Print("Error. Couldn't detect proper currency pair for 2-pair adjustment calculation. Cross currency: ", cross_currency, ". Account currency: ", AccCurrency, ".");
        return false;
    }

    add_ref_symbol = GetSymbolByCurrencies(cross_currency, profit_currency, FOREX_SYMBOLS_ONLY); 
    if (add_ref_symbol == NULL) add_ref_symbol = GetSymbolByCurrencies(cross_currency, profit_currency, NONFOREX_SYMBOLS_ONLY);
    add_ref_mode = false; // If found, we've got USD/CHF. Notice that mode is swapped for cross/profit compared to cross/acc, because it is used in the opposite way.

    // Failed.
    if (add_ref_symbol == NULL)
    {
        // Reversing currencies.
        add_ref_symbol = GetSymbolByCurrencies(profit_currency, cross_currency, FOREX_SYMBOLS_ONLY);
        if (add_ref_symbol == NULL) add_ref_symbol = GetSymbolByCurrencies(profit_currency, cross_currency, NONFOREX_SYMBOLS_ONLY);
        add_ref_mode = true; // If found, we've got CHF/USD. Notice that mode is swapped for profit/cross compared to acc/cross, because it is used in the opposite way.
    }
    if (add_ref_symbol == NULL)
    {
        Print("Error. Couldn't detect proper currency pair for 2-pair adjustment calculation. Cross currency: ", cross_currency, ". Chart's pair currency: ", profit_currency, ".");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on current prices.       |
//+------------------------------------------------------------------+
double GetCurrencyCorrectionCoefficient(MqlTick &tick, const mode_of_operation mode, const bool ReferenceSymbolMode)
{
    if ((tick.ask == 0) || (tick.bid == 0)) return -1; // Data is not yet ready.
    if (mode == Risk)
    {
        // Reverse quote.
        if (ReferenceSymbolMode)
        {
            // Using Buy price for reverse quote.
            return tick.ask;
        }
        // Direct quote.
        else
        {
            // Using Sell price for direct quote.
            return(1 / tick.bid);
        }
    }
    else if (mode == Reward)
    {
        // Reverse quote.
        if (ReferenceSymbolMode)
        {
            // Using Sell price for reverse quote.
            return tick.bid;
        }
        // Direct quote.
        else
        {
            // Using Buy price for direct quote.
            return(1 / tick.ask);
        }
    }
    return -1;
}
//+------------------------------------------------------------------+