//+------------------------------------------------------------------+
//|                                                    Stop-Out Line |
//|                                      Copyright © 2025, EarnForex |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+
#property copyright "www.EarnForex.com, 2025"
#property link      "https://www.earnforex.com/indicators/Stop-Out-Line/"
#property version   "1.00"
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
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pipValue = (tickValue / tickSize) * symbolPositionLots;

    // Calculate price movement needed to reach stop-out.
    double priceMovement = 0;
    if (pipValue > 0)
    {
        priceMovement = maxLoss / pipValue;
    }

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
//+------------------------------------------------------------------+