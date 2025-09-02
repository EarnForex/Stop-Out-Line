//+------------------------------------------------------------------+
//|                                                    Stop-Out Line |
//|                                      Copyright © 2025, EarnForex |
//|                                        https://www.earnforex.com |
//+------------------------------------------------------------------+
#property copyright "www.EarnForex.com, 2025"
#property link      "https://www.earnforex.com/indicators/Stop-Out-Line/"
#property version   "1.00"
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

    // Calculate pip value for the position
    double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
    double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
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
//+------------------------------------------------------------------+