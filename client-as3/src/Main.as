package
{
    import __AS3__.vec.Vector;
	import flash.display.Loader;
    import flash.display.Sprite;
    import flash.events.*;
    import flash.media.Microphone;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
    import flash.text.*;
    import flash.utils.*;
 
    /**
     * A real-time spectrum analyzer.
     *
     * Released under the MIT License
     *
     * Copyright (c) 2010 Gerald T. Beauregard
     *
     * Permission is hereby granted, free of charge, to any person obtaining a copy
     * of this software and associated documentation files (the "Software"), to
     * deal in the Software without restriction, including without limitation the
     * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
     * sell copies of the Software, and to permit persons to whom the Software is
     * furnished to do so, subject to the following conditions:
     *
     * The above copyright notice and this permission notice shall be included in
     * all copies or substantial portions of the Software.
     *
     * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
     * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
     * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
     * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
     * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
     * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
     * IN THE SOFTWARE.
     */
 
    [SWF(width='600', height='400', frameRate='30', backgroundColor='0xFFFFFF')]
    public class Main extends Sprite
    {
        private const SAMPLE_RATE:Number = 22050;   // Actual microphone sample rate (Hz)
        private const LOGN:uint = 11;               // Log2 FFT length
        private const N:uint = 1 << LOGN;         // FFT Length
        private const BUF_LEN:uint = N;             // Length of buffer for mic audio
        private const UPDATE_PERIOD:int = 20;       // Period of spectrum updates (ms)
 
        private var m_fft:FFT2;                     // FFT object
 
        private var m_tempRe:Vector.<Number>;     // Temporary buffer - real part
        private var m_tempIm:Vector.<Number>;     // Temporary buffer - imaginary part
        private var m_mag:Vector.<Number>;            // Magnitudes (at each of the frequencies below)
        private var m_freq:Vector.<Number>;           // Frequencies (for each of the magnitudes above)
        private var m_win:Vector.<Number>;            // Analysis window (Hanning)
 
        private var m_mic:Microphone;               // Microphone object
        private var m_writePos:uint = 0;            // Position to write new audio from mic
        private var m_buf:Vector.<Number> = null; // Buffer for mic audio
		private var lightOn:Boolean = false;
        private var m_tickTextAdded:Boolean = false;
		
		private var highestSound:Number = 0;
 
        private var m_timer:Timer;                  // Timer for updating spectrum
		private var firstClap:Boolean = true;
		private var totalSoundProduction:Number;
 
        /**
         *
         */
        public function Main()
        {
            var i:uint;
 
            // Set up the FFT
            m_fft = new FFT2();
            m_fft.init(LOGN);
            m_tempRe = new Vector.<Number>(N);
            m_tempIm = new Vector.<Number>(N);
            m_mag = new Vector.<Number>(N/2);
            //m_smoothMag = new Vector.<Number>(N/2);
 
            // Vector with frequencies for each bin number. Used
            // in the graphing code (not in the analysis itself).
            m_freq = new Vector.<Number>(N/2);
            for ( i = 0; i < N/2; i++ )
                m_freq[i] = i*SAMPLE_RATE/N;
 
            // Hanning analysis window
            m_win = new Vector.<Number>(N);
            for ( i = 0; i < N; i++ )
                m_win[i] = (4.0/N) * 0.5*(1-Math.cos(2*Math.PI*i/N));
 
            // Create a buffer for the input audio
            m_buf = new Vector.<Number>(BUF_LEN);
            for ( i = 0; i < BUF_LEN; i++ )
                m_buf[i] = 0.0;
 
            // Set up microphone input
            m_mic = Microphone.getMicrophone();
            m_mic.rate = SAMPLE_RATE/1000;
            m_mic.setSilenceLevel(0.0);         // Have the mic run non-stop, regardless of the input level
            m_mic.addEventListener( SampleDataEvent.SAMPLE_DATA, onMicSampleData );
 
            // Set up a timer to do periodic updates of the spectrum
            m_timer = new Timer(UPDATE_PERIOD);
            m_timer.addEventListener(TimerEvent.TIMER, updateSpectrum);
            m_timer.start();
        }
 
        /**
         * Called whether new microphone input data is available. See this call
         * above:
         *    m_mic.addEventListener( SampleDataEvent.SAMPLE_DATA, onMicSampleData );
         */
        private function onMicSampleData( event:SampleDataEvent ):void
        {
            // Get number of available input samples
            var len:uint = event.data.length/4;
 
            // Read the input data and stuff it into
            // the circular buffer
            for ( var i:uint = 0; i < len; i++ )
            {
                m_buf[m_writePos] = event.data.readFloat();
                m_writePos = (m_writePos+1)%BUF_LEN;
            }
        }
 
        /**
         * Called at regular intervals to update the spectrum
         */
        private function updateSpectrum( event:Event ):void
        {
            // Copy data from circular microphone audio
            // buffer into temporary buffer for FFT, while
            // applying Hanning window.
            var i:int;
            var pos:uint = m_writePos;
            for ( i = 0; i < N; i++ )
            {
                m_tempRe[i] = m_win[i]*m_buf[pos];
                pos = (pos+1)%BUF_LEN;
            }
 
            // Zero out the imaginary component
            for ( i = 0; i < N; i++ )
                m_tempIm[i] = 0.0;
 
            // Do FFT and get magnitude spectrum
            m_fft.run( m_tempRe, m_tempIm );
            for ( i = 0; i < N/2; i++ )
            {
                var re:Number = m_tempRe[i];
                var im:Number = m_tempIm[i];
                m_mag[i] = Math.sqrt(re*re + im*im);
            }
 
            // Convert to dB magnitude
            const SCALE:Number = 20/Math.LN10;
            for ( i = 0; i < N/2; i++ )
            {
                // 20 log10(mag) => 20/ln(10) ln(mag)
                // Addition of MIN_VALUE prevents log from returning minus infinity if mag is zero
                m_mag[i] = SCALE*Math.log( m_mag[i] + Number.MIN_VALUE );
            }
 
            // Draw the graph
            drawSpectrum( m_mag, m_freq );
        }
 
        /**
         * Draw a graph of the spectrum
         */
        private function drawSpectrum(
            mag:Vector.<Number>,
            freq:Vector.<Number> ):void
        {
            // Basic constants
            const MIN_FREQ:Number = 0;                  // Minimum frequency (Hz) on horizontal axis.
            const MAX_FREQ:Number = 4000;               // Maximum frequency (Hz) on horizontal axis.
            const FREQ_STEP:Number = 500;               // Interval between ticks (Hz) on horizontal axis.
            const MAX_DB:Number = -0.0;                 // Maximum dB magnitude on vertical axis.
            const MIN_DB:Number = -60.0;                // Minimum dB magnitude on vertical axis.
            const DB_STEP:Number = 10;                  // Interval between ticks (dB) on vertical axis.
            const TOP:Number  = 50;                     // Top of graph
            const LEFT:Number = 60;                     // Left edge of graph
            const HEIGHT:Number = 300;                  // Height of graph
            const WIDTH:Number = 500;                   // Width of graph
            const TICK_LEN:Number = 10;                 // Length of tick in pixels
            const LABEL_X:String = "Frequency (Hz)";    // Label for X axis
            const LABEL_Y:String = "dB";                // Label for Y axis
 
            // Derived constants
            const BOTTOM:Number = TOP+HEIGHT;                   // Bottom of graph
            const DBTOPIXEL:Number = HEIGHT/(MAX_DB-MIN_DB);    // Pixels/tick
            const FREQTOPIXEL:Number = WIDTH/(MAX_FREQ-MIN_FREQ);// Pixels/Hz
 
            //-----------------------
 
            var i:uint;
            var numPoints:uint;
 
            numPoints = mag.length;
            if ( mag.length != freq.length )
                trace( "mag.length != freq.length" );
 
           
 
            // -------------------------------------------------
            // The line in the graph
 
            // Ignore points that are too far to the left
            for ( i = 0; i < numPoints && freq[i] < MIN_FREQ; i++ )
            {
            }
 
            // For all remaining points within range of x-axis
            var firstPoint:Boolean = true;
			totalSoundProduction = 30000;
            for ( /**/; i < numPoints && freq[i] <= MAX_FREQ; i++ )
            {

				
				totalSoundProduction += mag[i];
				
    
            }
			
		
			
			if (totalSoundProduction > 15000 && firstClap) {
				firstClap = false;
				
				//trace('first high pitch');
				//trace(totalSoundProduction);
					
				
					setTimeout(function():void {
						//trace(totalSoundProduction);
						var time:uint = setInterval(function():void {
							if (totalSoundProduction > 15000) {
								trace("Double clap");
								switchLight();
								firstClap = true;
								clearInterval(time);
								
							}
						},10);
						
						setTimeout(function():void {
							firstClap = true;
							clearInterval(time);
						},300);
					},200);
			}
			//trace(totalSoundProduction);
        }
		private function switchLight():void {
			lightOn = !lightOn;
			var val:int = 0;
			if (lightOn) {
				val = 1;
			}
			var random:Number = Math.random();
			var makeRequest:URLLoader = new URLLoader();
			makeRequest.load(new URLRequest("http://192.168.192.15:8081/set?v=" + val + "&r=7&random="+random));			
		}
    }
}