// -------------------------------------------------------------------------------
//   Displays a stop-out line for the current symbol.
//   You can hide/show the line by pressing Shift+S.
//   
//   Version 1.00
//   Copyright 2025, EarnForex.com
//   https://www.earnforex.com/indicators/Stop-Out-Line/
// -------------------------------------------------------------------------------

using System;
using cAlgo.API;
using cAlgo.API.Internals;

namespace cAlgo
{
    [Indicator(IsOverlay = true, TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
    public class StopOutPriceLevel : Indicator
    {
        [Parameter("Update frequency (milliseconds)", DefaultValue = 100, MinValue = 50)]
        public int UpdateFrequencyMs { get; set; }
        
        [Parameter("Stop-out line color", DefaultValue = "Red")]
        public Color LineColor { get; set; }
        
        [Parameter("Stop-out line width", DefaultValue = 2, MinValue = 1, MaxValue = 5)]
        public int LineWidth { get; set; }
        
        [Parameter("Stop-out line style", DefaultValue = LineStyle.Solid)]
        public LineStyle LineStyle { get; set; }
        
        [Parameter("Show price label", DefaultValue = true)]
        public bool ShowLabel { get; set; }
        
        [Parameter("Line label prefix", DefaultValue = "STOP-OUT: ")]
        public string LineLabel { get; set; }

        // Global variables:
        private string LineObjectName = "StopOutPriceLine";
        private string LabelObjectName = "StopOutPriceLabel";
        private double StopOutPrice = 0;

        protected override void Initialize()
        {
            CalculateStopOutPrice();
            Timer.Start(TimeSpan.FromMilliseconds(UpdateFrequencyMs));

            // Subscribe to chart scroll events.
            Chart.ScrollChanged += OnChartScrollChanged;
            Chart.ZoomChanged += OnChartZoomChanged;

            // Subscribe to key events for hotkey.
            Chart.KeyDown += OnChartKeyDown;
        }

        public override void Calculate(int index)
        {
            // Calculate on new ticks only.
            if (IsLastBar)
            {
                CalculateStopOutPrice();
            }
        }

        protected override void OnTimer()
        {
            CalculateStopOutPrice();
        }

        private void OnChartScrollChanged(ChartScrollEventArgs obj)
        {
            // Update label position on chart change/scroll:
            UpdateLabelPosition();
        }

        private void OnChartZoomChanged(ChartZoomEventArgs obj)
        {
            // Update label position on chart zoom:
            UpdateLabelPosition();
        }

        private void OnChartKeyDown(ChartKeyboardEventArgs obj)
        {
            // Check for Shift+S hotkey.
            if (obj.ShiftKey && obj.Key == Key.S)
            {
                var line = Chart.FindObject(LineObjectName) as ChartHorizontalLine;
                if (line == null) return; 
                var label = Chart.FindObject(LabelObjectName) as ChartText;
                if (line.IsHidden)
                {
                    line.IsHidden = false;
                    if (label != null) label.IsHidden = false;
                }
                else
                {
                    line.IsHidden = true;
                    if (label != null) label.IsHidden = true;
                }
            }
        }

        // Calculate stop-out price based on current positions.
        private void CalculateStopOutPrice()
        {
            // Get account parameters.
            double equity = Account.Equity;
            double margin = Account.Margin;
            double stopOutLevel = Account.StopOutLevel; // Broker's stop-out level in %.
            
            // Check if there are open positions.
            if (margin == 0)
            {
                // No positions, remove the line.
                DeleteLineAndLabel();
                return;
            }
            
            // Calculate total position parameters for current symbol.
            int positionDirection = 0; // 1 for net long, -1 for net short.
            double netVolume = 0;
            
            // Scan all positions.
            foreach (var position in Positions)
            {
                // Check if position is for current symbol.
                if (position.SymbolName == Symbol.Name)
                {
                    if (position.TradeType == TradeType.Buy)
                    {
                        netVolume += position.VolumeInUnits;
                    }
                    else if (position.TradeType == TradeType.Sell)
                    {
                        netVolume -= position.VolumeInUnits;
                    }
                }
            }
            
            // Determine position direction.
            if (netVolume > 0) positionDirection = 1;  // Net long.
            else if (netVolume < 0) positionDirection = -1;  // Net short.
            else
            {
                // No positions, remove the line.
                DeleteLineAndLabel();
                return;
            }

            double symbolPositionVolume = Math.Abs(netVolume);

            // Calculate equity at stop-out.
            double equityAtStopOut = (stopOutLevel / 100.0) * margin;

            // Calculate maximum loss allowed.
            double maxLoss = equity - equityAtStopOut;

            // Get current price.
            double currentPrice;
            if (positionDirection == 1) currentPrice = Symbol.Bid; // Net long position is closed at Bid.
            else currentPrice = Symbol.Ask; // Net short position is closed at Ask.

            // Calculate pip value for the position.
            double pipValue = Symbol.PipValue * symbolPositionVolume;

            // Calculate price movement needed to reach stop-out.
            double priceMovement = 0;
            if (pipValue > 0)
            {
                priceMovement = (maxLoss / pipValue) * Symbol.PipSize;
            }

            // Calculate stop-out price based on position direction.
            if (positionDirection == 1) // Long position.
            {
                StopOutPrice = currentPrice - priceMovement;
            }
            else if (positionDirection == -1) // Short position.
            {
                double spread = Symbol.Ask - Symbol.Bid;
                StopOutPrice = currentPrice + priceMovement - spread; // Sell positions are closed at Ask, so the stop-out will happen when the current price goes to the Bid of the expected stop-out price. Hence, the stop-out line should be drawn at that Bid level.
            }

            // Ensure price is normalized.
            StopOutPrice = Math.Round(StopOutPrice, Symbol.Digits);

            // Draw or update the horizontal line.
            DrawStopOutLine();
        }

        // Draw stop-out line on chart.
        private void DrawStopOutLine()
        {
            if (StopOutPrice <= 0) return;
            
            // Create or move horizontal line.
            var line = Chart.FindObject(LineObjectName) as ChartHorizontalLine;
            if (line == null)
            {
                // Create new line.
                line = Chart.DrawHorizontalLine(LineObjectName, StopOutPrice, LineColor, LineWidth, LineStyle);
                line.IsInteractive = false;  // Make it non-selectable.
            }
            else
            {
                // Update existing line.
                line.Y = StopOutPrice;
                line.Color = LineColor;
                line.LineStyle = LineStyle;
                line.Thickness = LineWidth;
            }

            // Add or update label if enabled.
            if (ShowLabel) UpdateLabelPosition();
        }

        // Update label position to stay on the left side of visible chart.
        private void UpdateLabelPosition()
        {
            if (StopOutPrice <= 0 || !ShowLabel || Bars.Count == 0) return;

            string labelText = LineLabel + StopOutPrice.ToString("F" + Symbol.Digits);

            // Get the leftmost visible bar.
            int firstVisibleBar = Chart.FirstVisibleBarIndex;
            
            int labelBar = firstVisibleBar;
            if (labelBar < 0) labelBar = 0;
            if (labelBar >= Bars.Count) labelBar = Bars.Count - 1;

            // Get the time for this bar.
            DateTime labelTime = Bars.OpenTimes[labelBar];
            var label = Chart.FindObject(LabelObjectName) as ChartText;
            if (label == null)
            {
                // Create new label.
                label = Chart.DrawText(LabelObjectName, labelText, labelTime, StopOutPrice, LineColor);
                label.FontSize = 12;
                label.VerticalAlignment = VerticalAlignment.Top;  // Text appears above the price
                label.HorizontalAlignment = HorizontalAlignment.Right;
                label.IsInteractive = false;  // Make it non-selectable
            }
            else
            {
                // Update existing label.
                label.Text = labelText;
                label.Y = StopOutPrice;
                label.Time = labelTime;
            }
        }

        private void DeleteLineAndLabel()
        {
            Chart.RemoveObject(LineObjectName);
            Chart.RemoveObject(LabelObjectName);
            StopOutPrice = 0;
        }
    }
}
//+------------------------------------------------------------------+