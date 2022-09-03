#property link          "https://www.earnforex.com/metatrader-indicators/moving-average-crossover-alert/"
#property version       "1.04"
#property strict
#property copyright     "EarnForex.com - 2020-2022"
#property description   "Moving average crossover alert. Supports simple, exponential, smoothed, linear weighted, and TEMA."
#property description   " "
#property description   " "
#property description   " "
#property description   "Find More on EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots 2
#property indicator_color1 clrRed
#property indicator_color2 clrGreen
#property indicator_type1 DRAW_LINE
#property indicator_type2 DRAW_LINE
#property indicator_label1 "Fast MA"
#property indicator_label2 "Slow MA"

#include <MQLTA ErrorHandling.mqh>
#include <MQLTA Utils.mqh>

enum ENUM_TRADE_SIGNAL
{
    SIGNAL_BUY = 1,    // Buy
    SIGNAL_SELL = -1,  // Sell
    SIGNAL_NEUTRAL = 0 // Neutral
};

enum ENUM_CANDLE_TO_CHECK
{
    CURRENT_CANDLE = 0,  // Current candle
    CLOSED_CANDLE = 1    // Previous candle
};

enum ENUM_MA_METHOD_EXTENDED // Same as ENUM_MA_METHOD but with TEMA.
{
    MODE_SMA_,   // Simple
    MODE_EMA_,   // Exponential
    MODE_SMMA_,  // Smoothed
    MODE_LWMA_,  // Linear weighted
    MODE_TEMA    // TEMA (Triple exponential moving average)
};

input group "MQLTA Moving Average Crossover Alert"
input string IndicatorName = "MQLTA-MACA";                 // Indicator short name

input group "Indicator parameters"
input int MAFastPeriod = 25;                               // Fast moving average period
input int MAFastShift = 0;                                 // Fast moving average shift
input ENUM_MA_METHOD_EXTENDED MAFastMethod = MODE_SMA_;    // Fast moving average method
input ENUM_APPLIED_PRICE MAFastAppliedPrice = PRICE_CLOSE; // Fast moving average applied price
input int MASlowPeriod = 50;                               // Slow moving average period
input int MASlowShift = 0;                                 // Slow moving average shift
input ENUM_MA_METHOD_EXTENDED MASlowMethod = MODE_SMA_;    // Slow moving average method
input ENUM_APPLIED_PRICE MASlowAppliedPrice = PRICE_CLOSE; // Slow moving average applied price
input ENUM_CANDLE_TO_CHECK CandleToCheck = CURRENT_CANDLE; // Candle to use for analysis
input int BarsToScan = 500;                                // Number of candles to analyze

input group "Notification options"
input bool EnableNotify = false;                           // Enable notifications feature
input bool SendAlert = false;                              // Send alert notification
input bool SendApp = false;                                // Send notification to mobile
input bool SendEmail = false;                              // Send notification via email

input group "Drawing options"
input bool EnableDrawArrows = true;                        // Draw signal arrows
input uchar ArrowBuy = 241;                                // Buy arrow code
input uchar ArrowSell = 242;                               // Sell arrow code
input int ArrowSize = 3;                                   // Arrow size (1-5)
input color ArrowBuyColor = clrGreen;                      // Buy arrow color
input color ArrowSellColor = clrRed;                       // Sell arrow color

double BufferMASlow[];
double BufferMAFast[];

int BufferMASlowHandle, BufferMAFastHandle;

double Open[], Close[], High[], Low[];
datetime Time[];

datetime LastNotificationTime;
ENUM_TRADE_SIGNAL LastNotificationDirection;
int Shift = 0;

int OnInit(void)
{
    IndicatorSetString(INDICATOR_SHORTNAME, IndicatorName);

    OnInitInitialization();
    if (!OnInitPreChecksPass())
    {
        return INIT_FAILED;
    }
    
    InitialiseHandles();
    InitialiseBuffers();

    return INIT_SUCCEEDED;
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
    if ((rates_total <= MASlowPeriod) || (MASlowPeriod <= 0)) return 0;
    if ((rates_total <= MAFastPeriod) || (MAFastPeriod <= 0)) return 0;
    if (MAFastPeriod > MASlowPeriod) return 0;

    bool IsNewCandle = CheckIfNewCandle();
    
    if (Bars(Symbol(), PERIOD_CURRENT) < (MASlowPeriod + MASlowShift))
    {
        Print("Not Enough Historical Candles");
        return 0;
    }

    int pos = 0, upTo;
    if ((prev_calculated == 0) || (IsNewCandle))
    {
        upTo = BarsToScan - 1;
    }
    else
    {
        upTo = 0;
    }

    if (IsStopped()) return 0;
    
    if ((CopyBuffer(BufferMAFastHandle, 0, -MAFastShift, upTo + 1, BufferMAFast) <= 0) ||
        (CopyBuffer(BufferMASlowHandle, 0, -MASlowShift, upTo + 1, BufferMASlow) <= 0))
    {
        Print("Failed to create the indicator! Error: ", GetLastErrorText(GetLastError()), " - ", GetLastError());
        return 0;
    }

    for (int i = pos; (i <= upTo) && (!IsStopped()); i++)
    {
        Open[i] = iOpen(Symbol(), PERIOD_CURRENT, i);
        Low[i] = iLow(Symbol(), PERIOD_CURRENT, i);
        High[i] = iHigh(Symbol(), PERIOD_CURRENT, i);
        Close[i] = iClose(Symbol(), PERIOD_CURRENT, i);
        Time[i] = iTime(Symbol(), PERIOD_CURRENT, i);
    }

    if ((IsNewCandle) || (prev_calculated == 0))
    {
        if (EnableDrawArrows) DrawArrows();
    }

    if (EnableDrawArrows) DrawArrow(0);

    if (EnableNotify) NotifyHit();

    return rates_total;
}

void OnDeinit(const int reason)
{
    CleanChart();
}

void OnInitInitialization()
{
    LastNotificationTime = TimeCurrent();
    LastNotificationDirection = SIGNAL_NEUTRAL;
    Shift = CandleToCheck;
}

bool OnInitPreChecksPass()
{
    if ((MASlowPeriod <= 0) || (MAFastPeriod <= 0) || (MAFastPeriod > MASlowPeriod))
    {
        Print("Wrong input parameter");
        return false;
    }
    return true;
}

void CleanChart()
{
    ObjectsDeleteAll(ChartID(), IndicatorName);
}

void InitialiseHandles()
{
    if (MAFastMethod == MODE_TEMA)
    {
        BufferMAFastHandle = iTEMA(Symbol(), PERIOD_CURRENT, MAFastPeriod, MAFastShift, MAFastAppliedPrice);
    }
    else
    {
        BufferMAFastHandle = iMA(Symbol(), PERIOD_CURRENT, MAFastPeriod, MAFastShift, ENUM_MA_METHOD(MAFastMethod), MAFastAppliedPrice);
    }
    if (MASlowMethod == MODE_TEMA)
    {
        BufferMASlowHandle = iTEMA(Symbol(), PERIOD_CURRENT, MASlowPeriod, MASlowShift, MASlowAppliedPrice);
    }
    else
    {
        BufferMASlowHandle = iMA(Symbol(), PERIOD_CURRENT, MASlowPeriod, MASlowShift, ENUM_MA_METHOD(MASlowMethod), MASlowAppliedPrice);
    }
    ArrayResize(Open, BarsToScan);
    ArrayResize(High, BarsToScan);
    ArrayResize(Low, BarsToScan);
    ArrayResize(Close, BarsToScan);
    ArrayResize(Time, BarsToScan);
}

void InitialiseBuffers()
{
    ArraySetAsSeries(BufferMAFast, true);
    ArraySetAsSeries(BufferMASlow, true);
    SetIndexBuffer(0, BufferMAFast, INDICATOR_DATA);
    SetIndexBuffer(1, BufferMASlow, INDICATOR_DATA);
    PlotIndexSetInteger(0, PLOT_SHIFT, MAFastShift);
    PlotIndexSetInteger(1, PLOT_SHIFT, MASlowShift);
}

datetime NewCandleTime = TimeCurrent();
bool CheckIfNewCandle()
{
    if (NewCandleTime == iTime(Symbol(), 0, 0)) return false;
    else
    {
        NewCandleTime = iTime(Symbol(), 0, 0);
        return true;
    }
}

// Check if it is a trade Signla 0 - Neutral, 1 - Buy, -1 - Sell
ENUM_TRADE_SIGNAL IsSignal(int i)
{
    int j = i + Shift;

    // Prevent array out of range error (negative index) for when the MA shift is negative.
    if ((j + MAFastShift < 0) || (j + MASlowShift < 0)) return SIGNAL_NEUTRAL;
    // Prevent array out of range error when not enough bars.
    if (j + 1 + MASlowShift >= iBars(Symbol(), Period())) return SIGNAL_NEUTRAL;

    if ((BufferMAFast[j + 1 + MAFastShift] < BufferMASlow[j + 1 + MASlowShift]) && (BufferMAFast[j + MAFastShift] > BufferMASlow[j + MASlowShift])) return SIGNAL_BUY;
    if ((BufferMAFast[j + 1 + MAFastShift] > BufferMASlow[j + 1 + MASlowShift]) && (BufferMAFast[j + MAFastShift] < BufferMASlow[j + MASlowShift])) return SIGNAL_SELL;

    return SIGNAL_NEUTRAL;
}

void NotifyHit()
{
    if (!EnableNotify) return;
    if ((!SendAlert) && (!SendApp) && (!SendEmail)) return;
    if ((CandleToCheck == CLOSED_CANDLE) && (Time[0] <= LastNotificationTime)) return;
    ENUM_TRADE_SIGNAL Signal = IsSignal(0);
    if (Signal == SIGNAL_NEUTRAL)
    {
        LastNotificationDirection = Signal;
        return;
    }
    if (Signal == LastNotificationDirection) return;
    string EmailSubject = IndicatorName + " " + Symbol() + " Notification ";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n\r\n" + IndicatorName + " Notification for " + Symbol() + " @ " + EnumToString(Period()) + "\r\n\r\n";
    string AlertText = "";
    string AppText = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + " - " + IndicatorName + " - " + Symbol() + " @ " + EnumToString(Period()) + " - ";
    string Text = "";

    Text += "Slow and Fast Moving Average Crossed - " + ((Signal == SIGNAL_SELL) ? "Sell" : "Buy");

    EmailBody += Text;
    AlertText += Text;
    AppText += Text;
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
    LastNotificationTime = Time[0];
    LastNotificationDirection = Signal;
}

void DrawArrows()
{
    RemoveArrows();
    if ((!EnableDrawArrows) || (BarsToScan == 0)) return;
    int MaxBars = Bars(Symbol(), PERIOD_CURRENT);
    if (MaxBars > BarsToScan) MaxBars = BarsToScan;
    for (int i = MaxBars - 2; i >= 1; i--)
    {
        DrawArrow(i);
    }
}

void RemoveArrows()
{
    ObjectsDeleteAll(ChartID(), IndicatorName + "-ARWS-");
}

void DrawArrow(int i)
{
    RemoveArrowCurr();
    if (!EnableDrawArrows)
    {
        RemoveArrows();
        return;
    }
    ENUM_TRADE_SIGNAL Signal = IsSignal(i);
    if (Signal == SIGNAL_NEUTRAL) return;
    datetime ArrowDate = iTime(Symbol(), 0, i);
    string ArrowName = IndicatorName + "-ARWS-" + IntegerToString(ArrowDate);
    double ArrowPrice = 0;
    uchar ArrowType = 0;
    color ArrowColor = 0;
    int ArrowAnchor = 0;
    string ArrowDesc = "";
    if (Signal == SIGNAL_BUY)
    {
        ArrowPrice = Low[i];
        ArrowType = ArrowBuy;
        ArrowColor = ArrowBuyColor;
        ArrowAnchor = ANCHOR_TOP;
        ArrowDesc = "BUY";
    }
    if (Signal == SIGNAL_SELL)
    {
        ArrowPrice = High[i];
        ArrowType = ArrowSell;
        ArrowColor = ArrowSellColor;
        ArrowAnchor = ANCHOR_BOTTOM;
        ArrowDesc = "SELL";
    }
    ObjectCreate(0, ArrowName, OBJ_ARROW, 0, ArrowDate, ArrowPrice);
    ObjectSetInteger(0, ArrowName, OBJPROP_COLOR, ArrowColor);
    ObjectSetInteger(0, ArrowName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, ArrowName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, ArrowName, OBJPROP_ANCHOR, ArrowAnchor);
    ObjectSetInteger(0, ArrowName, OBJPROP_ARROWCODE, ArrowType);
    ObjectSetInteger(0, ArrowName, OBJPROP_WIDTH, ArrowSize);
    ObjectSetInteger(0, ArrowName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, ArrowName, OBJPROP_BGCOLOR, ArrowColor);
    ObjectSetString(0, ArrowName, OBJPROP_TEXT, ArrowDesc);
}

void RemoveArrowCurr()
{
    datetime ArrowDate = iTime(Symbol(), 0, Shift);
    string ArrowName = IndicatorName + "-ARWS-" + IntegerToString(ArrowDate);
    ObjectDelete(0, ArrowName);
}
//+------------------------------------------------------------------+