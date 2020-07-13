
////////////////////////////////////////////////////
//
//  W_AnalogRead is used to visiualze analog voltage values
//
//  Created: AJ Keller
//
//
///////////////////////////////////////////////////,

class W_PulseSensor extends Widget {

    //to see all core variables/methods of the Widget class, refer to Widget.pde
    //put your custom variables here...

    private int numAnalogReadBars;
    float xF, yF, wF, hF;
    float arPadding;
    float ar_x, ar_y, ar_h, ar_w; // values for actual time series chart (rectangle encompassing all analogReadBars)
    float plotBottomWell;
    float playbackWidgetHeight;
    int analogReadBarHeight;

    PulseReadBar[] pulseReadBars;

    int[] xLimOptions = {0, 1, 3, 5, 10, 20}; // number of seconds (x axis of graph)
    int[] yLimOptions = {0, 50, 100, 200, 400, 1000, 10000}; // 0 = Autoscale ... everything else is uV

    private boolean allowSpillover = false;
    private boolean visible = true;

    //Initial dropdown settings
    private int arInitialVertScaleIndex = 5;
    private int arInitialHorizScaleIndex = 0;

    /////////////////////////////////////////
    int padding = 15;
    color eggshell;
    color pulseWave;
    int[] PulseWaveY;      // HOLDS HEARTBEAT WAVEFORM DATA
    int[] BPMwaveY;        // HOLDS BPM WAVEFORM DATA
    boolean rising;

    // Synthetic Wave Generator Stuff
    float theta;  // Start angle at 0
    float amplitude;  // Height of wave
    int syntheticMultiplier;
    long thisTime;
    long thatTime;
    int refreshRate;

    // Pulse Sensor Beat Finder Stuff
    // ASSUMES 250Hz SAMPLE RATE
    int[] rate;                    // array to hold last ten IBI values
    int sampleCounter;          // used to determine pulse timing
    int lastBeatTime;           // used to find IBI
    int P = 512;                      // used to find peak in pulse wave, seeded
    int T = 512;                     // used to find trough in pulse wave, seeded
    int thresh = 530;                // used to find instant moment of heart beat, seeded
    int amp = 0;                   // used to hold amplitude of pulse waveform, seeded
    boolean firstBeat = true;        // used to seed rate array so we startup with reasonable BPM
    boolean secondBeat = false;      // used to seed rate array so we startup with reasonable BPM
    public int BPM = 0;                   // int that holds raw Analog in 0. updated every 2mS
    int Signal;                // holds the incoming raw data
    public int IBI = 600;             // int that holds the time interval between beats! Must be seeded!
    boolean Pulse = false;     // "True" when User's live heartbeat is detected. "False" when not a "live beat".
    int lastProcessedDataPacketInd = 0;
    int PulseBuffSize = 0;
    int BPMbuffSize = 100;
    /////////////////////////////////////////

    Button_obci analogModeButton;

    private AnalogCapableBoard analogBoard;

    W_PulseSensor(PApplet _parent) {
        super(_parent); //calls the parent CONSTRUCTOR method of Widget (DON'T REMOVE)

        //Analog Read settings
        settings.arVertScaleSave = 5; //updates in VertScale_AR()
        settings.arHorizScaleSave = 0; //updates in Duration_AR()

        //This is the protocol for setting up dropdowns.
        //Note that these 3 dropdowns correspond to the 3 global functions below
        //You just need to make sure the "id" (the 1st String) has the same name as the corresponding function
        addDropdown("VertScale_Pulse", "Vert Scale", Arrays.asList(settings.arVertScaleArray), arInitialVertScaleIndex);
        addDropdown("Duration_Pulse", "Window", Arrays.asList(settings.arHorizScaleArray), arInitialHorizScaleIndex);

        //set number of analog reads
        numAnalogReadBars = 3;

        xF = float(x); //float(int( ... is a shortcut for rounding the float down... so that it doesn't creep into the 1px margin
        yF = float(y);
        wF = float(w);
        hF = float(h);

        plotBottomWell = 45.0; //this appears to be an arbitrary vertical space adds GPlot leaves at bottom, I derived it through trial and error
        arPadding = 10.0;
        ar_x = xF + arPadding;
        ar_y = yF + (arPadding);
        ar_w = wF - arPadding*2;
        ar_h = hF - playbackWidgetHeight - plotBottomWell - (arPadding*2);
        analogReadBarHeight = int(ar_h/numAnalogReadBars);

        analogModeButton = new Button_obci((int)(x + 3), (int)(y + 3 - navHeight), 128, navHeight - 6, "ANALOG TOGGLE", 12);
        analogModeButton.setCornerRoundess((int)(navHeight-6));
        analogModeButton.setFont(p5,12);
        analogModeButton.textColorNotActive = color(255);
        analogModeButton.hasStroke(false);
        if (selectedProtocol == BoardProtocol.WIFI) {
            analogModeButton.setHelpText("Click this button to activate/deactivate analog read on Cyton pins A5(D11) and A6(D12).");
        } else {
            analogModeButton.setHelpText("Click this button to activate/deactivate analog read on Cyton pins A5(D11), A6(D12) and A7(D13).");
        }

        PulseBuffSize = 3 * currentBoard.getSampleRate(); // Originally 400
        PulseWaveY = new int[PulseBuffSize];
        BPMwaveY = new int[BPMbuffSize];
        rate = new int[10];
        initializePulseFinderVariables();

        //create our channel bars and populate our pulseReadBars array!
        pulseReadBars = new PulseReadBar[numAnalogReadBars];
        for(int i = 0; i < numAnalogReadBars; i++) {
            int analogReadBarY = int(ar_y) + i*(analogReadBarHeight); //iterate through bar locations
            PulseReadBar tempBar = new PulseReadBar(_parent, i, int(ar_x), analogReadBarY, int(ar_w), analogReadBarHeight); //int _channelNumber, int _x, int _y, int _w, int _h
            pulseReadBars[i] = tempBar;
            pulseReadBars[i].adjustVertScale(yLimOptions[arInitialVertScaleIndex]);
            //sync horiz axis to Time Series by default
            pulseReadBars[i].adjustTimeAxis(w_timeSeries.xLimOptions[settings.tsHorizScaleSave]);
        }

        analogBoard = (AnalogCapableBoard)currentBoard;
    }

    public boolean isVisible() {
        return visible;
    }

    public int getNumAnalogReads() {
        return numAnalogReadBars;
    }

    public void setVisible(boolean _visible) {
        visible = _visible;
    }

    void update() {
        if(visible) {
            super.update(); //calls the parent update() method of Widget (DON'T REMOVE)

            //update channel bars ... this means feeding new EEG data into plots
            for(int i = 0; i < numAnalogReadBars; i++) {
                pulseReadBars[i].update();
            }

            //ignore top left button interaction when widgetSelector dropdown is active
            ignoreButtonCheck(analogModeButton);
        }

        updateOnOffButton();
    }

    private void updateOnOffButton() {	
        if (analogBoard.isAnalogActive()) {	
            analogModeButton.setString("Turn Analog Read Off");	
            analogModeButton.setIgnoreHover(!analogBoard.canDeactivateAnalog());
            if(!analogBoard.canDeactivateAnalog()) {
                analogModeButton.setColorNotPressed(color(128));
            }
        }
        else {
            analogModeButton.setString("Turn Analog Read On");	
            analogModeButton.setIgnoreHover(false);
            analogModeButton.setColorNotPressed(color(57,128,204));
        }
    }

    void draw() {
        if(visible) {
            super.draw(); //calls the parent draw() method of Widget (DON'T REMOVE)

            //remember to refer to x,y,w,h which are the positioning variables of the Widget class
            pushStyle();
            //draw channel bars
            analogModeButton.draw();
            if (analogBoard.isAnalogActive()) {
                for(int i = 0; i < numAnalogReadBars; i++) {
                    pulseReadBars[i].draw();
                }
            }
            popStyle();
        }
    }

    void screenResized() {
        super.screenResized(); //calls the parent screenResized() method of Widget (DON'T REMOVE)

        xF = float(x); //float(int( ... is a shortcut for rounding the float down... so that it doesn't creep into the 1px margin
        yF = float(y);
        wF = float(w);
        hF = float(h);

        ar_x = xF + arPadding;
        ar_y = yF + (arPadding);
        ar_w = wF - arPadding*2;
        ar_h = hF - playbackWidgetHeight - plotBottomWell - (arPadding*2);
        analogReadBarHeight = int(ar_h/numAnalogReadBars);

        for(int i = 0; i < numAnalogReadBars; i++) {
            int analogReadBarY = int(ar_y) + i*(analogReadBarHeight); //iterate through bar locations
            pulseReadBars[i].screenResized(int(ar_x), analogReadBarY, int(ar_w), analogReadBarHeight); //bar x, bar y, bar w, bar h
        }

        analogModeButton.setPos((int)(x + 3), (int)(y + 3 - navHeight));
    }

    void mousePressed() {
        super.mousePressed(); //calls the parent mousePressed() method of Widget (DON'T REMOVE)

        if (analogModeButton.isMouseHere()) {
            analogModeButton.setIsActive(true);
        }
    }

    void mouseReleased() {
        super.mouseReleased(); //calls the parent mouseReleased() method of Widget (DON'T REMOVE)

        if(analogModeButton.isActive && analogModeButton.isMouseHere()) {
            // println("analogModeButton...");
            if (!analogBoard.isAnalogActive()) {
                analogBoard.setAnalogActive(true);
                if (selectedProtocol == BoardProtocol.WIFI) {
                    output("Starting to read analog inputs on pin marked A5 (D11) and A6 (D12)");
                } else {
                    output("Starting to read analog inputs on pin marked A5 (D11), A6 (D12) and A7 (D13)");
                }
            } else {
                analogBoard.setAnalogActive(false);
                output("Starting to read accelerometer");
            }
        }
        analogModeButton.setIsActive(false);
    }

    void initializePulseFinderVariables(){
        sampleCounter = 0;
        lastBeatTime = 0;
        P = 512;
        T = 512;
        thresh = 530;
        amp = 0;
        firstBeat = true;
        secondBeat = false;
        BPM = 0;
        Signal = 512;
        IBI = 600;
        Pulse = false;

        theta = 0.0;
        amplitude = 300;
        syntheticMultiplier = 1;

        thatTime = millis();

        for(int i=0; i<PulseWaveY.length; i++){
            PulseWaveY[i] = Signal;
        }

        for(int i=0; i<BPMwaveY.length; i++){
            BPMwaveY[i] = BPM;
        }

    }

    private void addBPM(int bpm) {
        for(int i=0; i<BPMwaveY.length-1; i++){
            BPMwaveY[i] = BPMwaveY[i+1];
        }
        BPMwaveY[BPMwaveY.length-1] = bpm;
    }

    public int getBPM() {
        return BPM;
    }

    public int getIBI() {
        return IBI;
    }
    // THIS IS THE BEAT FINDING FUNCTION
    // BASED ON CODE FROM World Famous Electronics, MAKERS OF PULSE SENSOR
    // https://github.com/WorldFamousElectronics/PulseSensor_Amped_Arduino
    public void processSignal(int sample){                         // triggered when Timer2 counts to 124
        // cli();                                      // disable interrupts while we do this
        // Signal = analogRead(pulsePin);              // read the Pulse Sensor
        sampleCounter += (4 * syntheticMultiplier);                         // keep track of the time in mS with this variable
        int N = sampleCounter - lastBeatTime;       // monitor the time since the last beat to avoid noise

            //  find the peak and trough of the pulse wave
        if(sample < thresh && N > (IBI/5)*3){       // avoid dichrotic noise by waiting 3/5 of last IBI
            if (sample < T){                        // T is the trough
                T = sample;                         // keep track of lowest point in pulse wave
            }
        }

        if(sample > thresh && sample > P){          // thresh condition helps avoid noise
            P = sample;                             // P is the peak
        }                                        // keep track of highest point in pulse wave

        //  NOW IT'S TIME TO LOOK FOR THE HEART BEAT
        // signal surges up in value every time there is a pulse
        if (N > 250){                                   // avoid high frequency noise
            if ( (sample > thresh) && (Pulse == false) && (N > (IBI/5)*3) ){
                Pulse = true;                               // set the Pulse flag when we think there is a pulse
                IBI = sampleCounter - lastBeatTime;         // measure time between beats in mS
                lastBeatTime = sampleCounter;               // keep track of time for next pulse

                if(secondBeat){                        // if this is the second beat, if secondBeat == TRUE
                    secondBeat = false;                  // clear secondBeat flag
                    for(int i=0; i<=9; i++){             // seed the running total to get a realisitic BPM at startup
                        rate[i] = IBI;
                    }
                }

                if(firstBeat){                         // if it's the first time we found a beat, if firstBeat == TRUE
                    firstBeat = false;                   // clear firstBeat flag
                    secondBeat = true;                   // set the second beat flag
                    // sei();                               // enable interrupts again
                    return;                              // IBI value is unreliable so discard it
                }


                // keep a running total of the last 10 IBI values
                int runningTotal = 0;                  // clear the runningTotal variable

                for(int i=0; i<=8; i++){                // shift data in the rate array
                    rate[i] = rate[i+1];                  // and drop the oldest IBI value
                    runningTotal += rate[i];              // add up the 9 oldest IBI values
                }

                rate[9] = IBI;                          // add the latest IBI to the rate array
                runningTotal += rate[9];                // add the latest IBI to runningTotal
                runningTotal /= 10;                     // average the last 10 IBI values
                BPM = 60000/runningTotal;               // how many beats can fit into a minute? that's BPM!
                BPM = constrain(BPM,0,200);
                addBPM(BPM);
            }
        }

        if (sample < thresh && Pulse == true){   // when the values are going down, the beat is over
            // digitalWrite(blinkPin,LOW);            // turn off pin 13 LED
            Pulse = false;                         // reset the Pulse flag so we can do it again
            amp = P - T;                           // get amplitude of the pulse wave
            thresh = amp/2 + T;                    // set thresh at 50% of the amplitude
            P = thresh;                            // reset these for next time
            T = thresh;
        }

        if (N > 2500){                           // if 2.5 seconds go by without a beat
            thresh = 530;                          // set thresh default
            P = 512;                               // set P default
            T = 512;                               // set T default
            lastBeatTime = sampleCounter;          // bring the lastBeatTime up to date
            firstBeat = true;                      // set these to avoid noise
            secondBeat = false;                    // when we get the heartbeat back
        }

        // sei();                                   // enable interrupts when youre done!
    }// end processSignal
};

//These functions need to be global! These functions are activated when an item from the corresponding dropdown is selected
void VertScale_Pulse(int n) {
    settings.arVertScaleSave = n;
    for(int i = 0; i < w_analogRead.numAnalogReadBars; i++) {
            w_pulseSensor.pulseReadBars[i].adjustVertScale(w_analogRead.yLimOptions[n]);
    }
}

//triggered when there is an event in the LogLin Dropdown
void Duration_Pulse(int n) {
    // println("adjust duration to: " + w_analogRead.pulseReadBars[i].adjustTimeAxis(n));
    //set analog read x axis to the duration selected from dropdown
    settings.arHorizScaleSave = n;

    //Sync the duration of Time Series, Accelerometer, and Analog Read(Cyton Only)
    for(int i = 0; i < w_analogRead.numAnalogReadBars; i++) {
        if (n == 0) {
            w_pulseSensor.pulseReadBars[i].adjustTimeAxis(w_timeSeries.xLimOptions[settings.tsHorizScaleSave]);
        } else {
            w_pulseSensor.pulseReadBars[i].adjustTimeAxis(w_analogRead.xLimOptions[n]);
        }
    }
}

//========================================================================================================================
//                      Analog Voltage BAR CLASS -- Implemented by Analog Read Widget Class
//========================================================================================================================
//this class contains the plot and buttons for a single channel of the Time Series widget
//one of these will be created for each channel (4, 8, or 16)
class PulseReadBar{

    private int analogInputPin;
    private String dataTypeString;
    private int x, y, w, h;
    private boolean isOn; //true means data is streaming and channel is active on hardware ... this will send message to OpenBCI Hardware

    private GPlot plot; //the actual grafica-based GPlot that will be rendering the Time Series trace
    private GPointsArray analogReadPoints;
    private int nPoints;
    private int numSeconds;
    private float timeBetweenPoints;

    private color channelColor; //color of plot trace

    private boolean isAutoscale; //when isAutoscale equals true, the y-axis of each channelBar will automatically update to scale to the largest visible amplitude
    private int autoScaleYLim = 0;

    private TextBox analogValue;
    private TextBox pulseDataType;

    private boolean drawAnalogValue;
    private int lastProcessedDataPacketInd = 0;

    private AnalogCapableBoard analogBoard;

    PulseReadBar(PApplet _parent, int _analogInputPin, int _x, int _y, int _w, int _h) { // channel number, x/y location, height, width

        analogInputPin = _analogInputPin;
        switch (analogInputPin) {
            case 0:
                dataTypeString = "Raw Data";
                break;
            case 1:
                dataTypeString = "Pulse";
                break;
            case 2:
                dataTypeString = "IBI";
                break;
        }
        dataTypeString = str(analogInputPin);
        isOn = true;

        x = _x;
        y = _y;
        w = _w;
        h = _h;

        numSeconds = 20;
        plot = new GPlot(_parent);
        plot.setPos(x + 36 + 4, y);
        plot.setDim(w - 36 - 4, h);
        plot.setMar(0f, 0f, 0f, 0f);
        plot.setLineColor((int)channelColors[(analogInputPin)%8]);
        plot.setXLim(-3.2,-2.9);
        plot.setYLim(-200,200);
        plot.setPointSize(2);
        plot.setPointColor(0);
        plot.setAllFontProperties("Arial", 0, 14);
        if(analogInputPin == 2) {
            plot.getXAxis().setAxisLabelText("Time (s)");
        }

        initArrays();

        analogValue = new TextBox("t", x + 36 + 4 + (w - 36 - 4) - 2, y + h);
        analogValue.textColor = color(bgColor);
        analogValue.alignH = RIGHT;
        // analogValue.alignV = TOP;
        analogValue.drawBackground = true;
        analogValue.backgroundColor = color(255,255,255,125);

        pulseDataType = new TextBox(dataTypeString, x+3, y + int(h/2.0) + 7);
        pulseDataType.textColor = color(bgColor);
        pulseDataType.alignH = CENTER;

        drawAnalogValue = true;
        analogBoard = (AnalogCapableBoard) currentBoard;
    }

    void initArrays() {
        nPoints = nPointsBasedOnDataSource();
        timeBetweenPoints = (float)numSeconds / (float)nPoints;
        analogReadPoints = new GPointsArray(nPoints);

        for (int i = 0; i < nPoints; i++) {
            float time = calcTimeAxis(i);
            float analog_value = 0.0; //0.0 for all points to start
            analogReadPoints.set(i, time, analog_value, "");
        }

        plot.setPoints(analogReadPoints); //set the plot with 0.0 for all auxReadPoints to start
    }

    void update() {

         // early out if unactive
        if (!analogBoard.isAnalogActive()) {
            return;
        }

        // update data in plot
        updatePlotPoints();
        if(isAutoscale) {
            autoScale();
        }

        //Fetch the last value in the buffer to display on screen
        float val = analogReadPoints.getY(nPoints-1);
        analogValue.string = String.format(getFmt(val),val);
        println(w_pulseSensor.getIBI());
    }

    void draw() {
        pushStyle();

        //draw plot
        stroke(31,69,110, 50);
        fill(color(125,30,12,30));

        rect(x + 36 + 4, y, w - 36 - 4, h);

        plot.beginDraw();
        plot.drawBox(); // we won't draw this eventually ...
        plot.drawGridLines(0);
        plot.drawLines();

        if(analogInputPin == 2) { //only draw the x axis label on the bottom channel bar
            plot.drawXAxis();
            plot.getXAxis().draw();
        }

        plot.endDraw();

        if(drawAnalogValue) {
            analogValue.draw();
            pulseDataType.draw();
        }

        popStyle();
    }

    private String getFmt(float val) {
        String fmt;
            if (val > 100.0f) {
                fmt = "%.0f";
            } else if (val > 10.0f) {
                fmt = "%.1f";
            } else {
                fmt = "%.2f";
            }
            return fmt;
    }

    float calcTimeAxis(int sampleIndex) {
        return -(float)numSeconds + (float)sampleIndex * timeBetweenPoints;
    }

    void updatePlotPoints() {
        List<double[]> allData = currentBoard.getData(nPoints);
        int[] channels = analogBoard.getAnalogChannels();

        if (channels.length == 0) {
            return;
        }
        
        for (int i=0; i < nPoints; i++) {
            float timey = calcTimeAxis(i);
            float value = 0;
            if (analogInputPin == 0) {
                try {
                    value = (float)allData.get(i)[channels[0]];
                    w_pulseSensor.processSignal(0);
                } catch (Exception e) {
                    e.printStackTrace();
                }
            } else if (analogInputPin == 1) { // PULSE RATE
                //println(w_pulseSensor.getIBI());
                //value = (float)w_pulseSensor.getBPM();
            } else if (analogInputPin == 2) { // IBI
                //value = (float)w_pulseSensor.getIBI();
            }
            
            analogReadPoints.set(i, timey, value, "");
        }

        plot.setPoints(analogReadPoints);
    }

    int nPointsBasedOnDataSource() {
        return numSeconds * currentBoard.getSampleRate();
    }

    void adjustTimeAxis(int _newTimeSize) {
        numSeconds = _newTimeSize;
        plot.setXLim(-_newTimeSize,0);

        nPoints = nPointsBasedOnDataSource();

        analogReadPoints = new GPointsArray(nPoints);
        if (_newTimeSize > 1) {
            plot.getXAxis().setNTicks(_newTimeSize);  //sets the number of axis divisions...
        }
        else {
            plot.getXAxis().setNTicks(10);
        }
        
        updatePlotPoints();
    }

    void adjustVertScale(int _vertScaleValue) {
        if(_vertScaleValue == 0) {
            isAutoscale = true;
        } else {
            isAutoscale = false;
            plot.setYLim(-_vertScaleValue, _vertScaleValue);
        }
    }

    void autoScale() {
        autoScaleYLim = 0;
        for(int i = 0; i < nPoints; i++) {
            if(int(abs(analogReadPoints.getY(i))) > autoScaleYLim) {
                autoScaleYLim = int(abs(analogReadPoints.getY(i)));
            }
        }
        plot.setYLim(-autoScaleYLim, autoScaleYLim);
    }

    void screenResized(int _x, int _y, int _w, int _h) {
        x = _x;
        y = _y;
        w = _w;
        h = _h;

        plot.setPos(x + 36 + 4, y);
        plot.setDim(w - 36 - 4, h);

        analogValue.x = x + 36 + 4 + (w - 36 - 4) - 2;
        analogValue.y = y + h;

        pulseDataType.x = x + 14;
        pulseDataType.y = y + int(h/2.0) + 7;
    }

};
