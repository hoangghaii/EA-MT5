//+------------------------------------------------------------------+
//| CControlPanel.mqh  - XAUUSD Scalper EA Phase 3                  |
//| On-chart toggle button + status label; fixed pixel positioning   |
//+------------------------------------------------------------------+
#property strict

class CControlPanel
{
private:
   string m_btnName;
   string m_lblName;
   bool   m_enabled;
   int    m_x;
   int    m_y;

   bool _createButton();
   bool _createLabel();

public:
   bool Init(int x, int y, ulong magic);
   void Deinit();
   bool IsEnabled()             { return m_enabled; }
   void UpdateStatus(string text);
   void OnClick(string objName);
};

//--- Create fixed-pixel OBJ_BUTTON at (m_x, m_y)
bool CControlPanel::_createButton()
{
   if(!ObjectCreate(0, m_btnName, OBJ_BUTTON, 0, 0, 0))
      return false;

   ObjectSetInteger(0, m_btnName, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, m_btnName, OBJPROP_XDISTANCE,  m_x);
   ObjectSetInteger(0, m_btnName, OBJPROP_YDISTANCE,  m_y);
   ObjectSetInteger(0, m_btnName, OBJPROP_XSIZE,      80);
   ObjectSetInteger(0, m_btnName, OBJPROP_YSIZE,      22);
   ObjectSetInteger(0, m_btnName, OBJPROP_FONTSIZE,   9);
   ObjectSetInteger(0, m_btnName, OBJPROP_COLOR,      clrLime);
   ObjectSetInteger(0, m_btnName, OBJPROP_BGCOLOR,    clrDarkGreen);
   ObjectSetInteger(0, m_btnName, OBJPROP_SELECTABLE, false);
   ObjectSetString(0,  m_btnName, OBJPROP_TEXT,       "EA: ON");
   return true;
}

//--- Create OBJ_LABEL status display below button
bool CControlPanel::_createLabel()
{
   if(!ObjectCreate(0, m_lblName, OBJ_LABEL, 0, 0, 0))
      return false;

   ObjectSetInteger(0, m_lblName, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, m_lblName, OBJPROP_XDISTANCE,  m_x);
   ObjectSetInteger(0, m_lblName, OBJPROP_YDISTANCE,  m_y + 28);
   ObjectSetInteger(0, m_lblName, OBJPROP_FONTSIZE,   8);
   ObjectSetInteger(0, m_lblName, OBJPROP_COLOR,      clrWhite);
   ObjectSetInteger(0, m_lblName, OBJPROP_SELECTABLE, false);
   ObjectSetString(0,  m_lblName, OBJPROP_TEXT,       "Status: IDLE");
   return true;
}

//--- Create panel objects; name-scope by magic to prevent collision on multi-instance
bool CControlPanel::Init(int x, int y, ulong magic)
{
   m_x       = x;
   m_y       = y;
   m_enabled = true;
   m_btnName = "EA_Toggle_" + IntegerToString((long)magic);
   m_lblName = "EA_Status_" + IntegerToString((long)magic);

   // Remove stale objects from previous load
   ObjectDelete(0, m_btnName);
   ObjectDelete(0, m_lblName);

   if(!_createButton() || !_createLabel())
   {
      Print("CControlPanel::Init - object creation failed");
      return false;
   }
   ChartRedraw(0);
   return true;
}

//--- Remove chart objects cleanly on EA removal
void CControlPanel::Deinit()
{
   ObjectDelete(0, m_btnName);
   ObjectDelete(0, m_lblName);
   ChartRedraw(0);
}

//--- Update status label text; only redraws on actual text change
void CControlPanel::UpdateStatus(string text)
{
   string current = ObjectGetString(0, m_lblName, OBJPROP_TEXT);
   if(current == text)
      return;
   ObjectSetString(0, m_lblName, OBJPROP_TEXT, text);
   ChartRedraw(0);
}

//--- Handle button click: toggle enable state, update visual feedback
void CControlPanel::OnClick(string objName)
{
   if(objName != m_btnName)
      return;

   m_enabled = !m_enabled;

   ObjectSetString(0,  m_btnName, OBJPROP_TEXT,   m_enabled ? "EA: ON"  : "EA: OFF");
   ObjectSetInteger(0, m_btnName, OBJPROP_COLOR,   m_enabled ? clrLime   : clrRed);
   ObjectSetInteger(0, m_btnName, OBJPROP_BGCOLOR, m_enabled ? clrDarkGreen : clrDarkRed);
   ObjectSetInteger(0, m_btnName, OBJPROP_STATE,   false); // release button visually

   ChartRedraw(0);
}
//+------------------------------------------------------------------+
