//+------------------------------------------------------------------+
//|                                                    Stop-Out Line |
//|                                      Copyright © 2025, EarnForex |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+
#property copyright "www.EarnForex.com, 2025"
#property link      "https://www.earnforex.com/indicators/Stop-Out-Line/"
#property version   "1.01"
#property indicator_plots 0
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
            ChartRedraw();
        }
    }
}

// Calculate stop-out price based on current positions.
void CalculateStopOutPrice()
{
    // Get account parameters using MT5 functions
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double stopOutLevel = AccountInfoDouble(ACCOUNT_MARGIN_SO_SO); // Broker's stop-out level.
    ENUM_ACCOUNT_STOPOUT_MODE stopOutMode = (ENUM_ACCOUNT_STOPOUT_MODE)AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE);

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

    // Scan all positions.
    int totalPositions = PositionsTotal();
    for (int i = 0; i < totalPositions; i++)
    {
        string posSymbol = PositionGetSymbol(i);
        if (PositionSelectByTicket(PositionGetTicket(i)))
        {
            // Check if position is for current symbol.
            if (posSymbol == _Symbol)
            {
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double posLots = PositionGetDouble(POSITION_VOLUME);
                if (posType == POSITION_TYPE_BUY)
                {
                    netLots += posLots;
                }
                else if (posType == POSITION_TYPE_SELL)
                {
                    netLots -= posLots;
                }
            }
        }
    }

    // Determine position direction.
    if (netLots > 0) positionDirection = 1;  // Net long.
    else if (netLots < 0) positionDirection = -1;  // Net short.
    else
    {
        // No positions in current symbol, remove the line.
        DeleteLineAndLabel();
        return;
    }

    double symbolPositionLots = MathAbs(netLots);

    // Calculate equity at stop-out based on the stop-out mode.
    double equityAtStopOut;
    if (stopOutMode == ACCOUNT_STOPOUT_MODE_PERCENT)
    {
        // Stop-out level is a percentage of margin.
        equityAtStopOut = (stopOutLevel / 100.0) * margin;
    }
    else // ACCOUNT_STOPOUT_MODE_MONEY
    {
        // Stop-out level is a free margin value in account currency.
        equityAtStopOut = equity - (AccountInfoDouble(ACCOUNT_MARGIN_FREE) - stopOutLevel);
    }

    // Calculate maximum loss allowed.
    double maxLoss = equity - equityAtStopOut;

    // Get current price.
    double currentPrice;
    MqlTick tick;
    SymbolInfoTick(_Symbol, tick);
    if (positionDirection == 1) currentPrice = tick.bid; // Net long position is closed at Bid.
    else currentPrice = tick.ask; // Net short position is closed at Ask.

    // Calculate pip value for the position
    AccCurrency = AccountInfoString(ACCOUNT_CURRENCY);
    
    double point_value_risk = CalculatePointValue(Risk);
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
        double spread = tick.ask - tick.bid;
        StopOutPrice = currentPrice + priceMovement - spread; // Sell positions are closed at Ask, so the stop-out will happen when the current price goes to the Bid of the expected stop-out price. Hence, the stop-out line should be drawn at that Bid level.
    }

    // Ensure price is normalized.
    StopOutPrice = NormalizeDouble(StopOutPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

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
    // Add or update label if enabled
    if (ShowLabel) UpdateLabelPosition();
    ChartRedraw();
}

// Update label position to stay on the left side of visible chart.
void UpdateLabelPosition()
{
    if (StopOutPrice <= 0 || !ShowLabel || iBars(Symbol(), Period()) == 0) return;

    string labelText = LineLabel + DoubleToString(StopOutPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

    // Get the leftmost visible bar.
    int firstVisibleBar = (int)ChartGetInteger(ChartID(), CHART_FIRST_VISIBLE_BAR);

    int labelBar = firstVisibleBar;
    if (labelBar < 0) labelBar = 0;

    // Get the time for this bar.
    datetime labelTime = iTime(Symbol(), Period(), labelBar);

    if (ObjectFind(ChartID(), LabelObjectName) < 0)
    {
        // Create new label
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
        // Update existing label
        ObjectSetDouble(ChartID(), LabelObjectName, OBJPROP_PRICE, StopOutPrice);
        ObjectSetInteger(ChartID(), LabelObjectName, OBJPROP_TIME, labelTime);
    }
    ObjectSetString(ChartID(), LabelObjectName, OBJPROP_TEXT, labelText);
    ChartRedraw();
}

void DeleteLineAndLabel()
{
    ObjectDelete(ChartID(), LineObjectName);
    ObjectDelete(ChartID(), LabelObjectName);
    ChartRedraw();
    StopOutPrice = 0;
}

enum mode_of_operation
{
    Risk,
    Reward
};

string AccCurrency;
double CalculatePointValue(mode_of_operation mode)
{
    string cp = Symbol();
    double UnitCost = CalculateUnitCost(cp, mode);
    double OnePoint = SymbolInfoDouble(cp, SYMBOL_POINT);
    return(UnitCost / OnePoint);
}

//+----------------------------------------------------------------------+
//| Returns unit cost either for Risk or for Reward mode.                |
//+----------------------------------------------------------------------+
double CalculateUnitCost(const string cp, const mode_of_operation mode)
{
    ENUM_SYMBOL_CALC_MODE CalcMode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(cp, SYMBOL_TRADE_CALC_MODE);

    // No-Forex.
    if ((CalcMode != SYMBOL_CALC_MODE_FOREX) && (CalcMode != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) && (CalcMode != SYMBOL_CALC_MODE_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES) && (CalcMode != SYMBOL_CALC_MODE_EXCH_FUTURES_FORTS))
    {
        double TickSize = SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_SIZE);
        double UnitCost = TickSize * SymbolInfoDouble(cp, SYMBOL_TRADE_CONTRACT_SIZE);
        string ProfitCurrency = SymbolInfoString(cp, SYMBOL_CURRENCY_PROFIT);
        if (ProfitCurrency == "RUR") ProfitCurrency = "RUB";

        // If profit currency is different from account currency.
        if (ProfitCurrency != AccCurrency)
        {
            return(UnitCost * CalculateAdjustment(ProfitCurrency, mode));
        }
        return UnitCost;
    }
    // With Forex instruments, tick value already equals 1 unit cost.
    else
    {
        if (mode == Risk) return SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_VALUE_LOSS);
        else return SymbolInfoDouble(cp, SYMBOL_TRADE_TICK_VALUE_PROFIT);
    }
}

//+-----------------------------------------------------------------------------------+
//| Calculates necessary adjustments for cases when GivenCurrency != AccountCurrency. |
//| Used in two cases: profit adjustment and margin adjustment.                       |
//+-----------------------------------------------------------------------------------+
double CalculateAdjustment(const string ProfitCurrency, const mode_of_operation mode)
{
    string ReferenceSymbol = GetSymbolByCurrencies(ProfitCurrency, AccCurrency);
    bool ReferenceSymbolMode = true;
    // Failed.
    if (ReferenceSymbol == NULL)
    {
        // Reversing currencies.
        ReferenceSymbol = GetSymbolByCurrencies(AccCurrency, ProfitCurrency);
        ReferenceSymbolMode = false;
    }
    // Everything failed.
    if (ReferenceSymbol == NULL)
    {
        Print("Error! Cannot detect proper currency pair for adjustment calculation: ", ProfitCurrency, ", ", AccCurrency, ".");
        ReferenceSymbol = Symbol();
        return 1;
    }
    MqlTick tick;
    SymbolInfoTick(ReferenceSymbol, tick);
    return GetCurrencyCorrectionCoefficient(tick, mode, ReferenceSymbolMode);
}

//+---------------------------------------------------------------------------+
//| Returns a currency pair with specified base currency and profit currency. |
//+---------------------------------------------------------------------------+
string GetSymbolByCurrencies(string base_currency, string profit_currency)
{
    // Cycle through all symbols.
    for (int s = 0; s < SymbolsTotal(false); s++)
    {
        // Get symbol name by number.
        string symbolname = SymbolName(s, false);

        // Skip non-Forex pairs.
        if ((SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX) && (SymbolInfoInteger(symbolname, SYMBOL_TRADE_CALC_MODE) != SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)) continue;

        // Get its base currency.
        string b_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_BASE);
        if (b_cur == "RUR") b_cur = "RUB";

        // Get its profit currency.
        string p_cur = SymbolInfoString(symbolname, SYMBOL_CURRENCY_PROFIT);
        if (p_cur == "RUR") p_cur = "RUB";
        
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

//+------------------------------------------------------------------+
//| Get profit correction coefficient based on profit currency,      |
//| calculation mode (profit or loss), reference pair mode (reverse  |
//| or direct), and current prices.                                  |
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