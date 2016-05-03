# Tempi Beat Detection

## Description

Beat detection is a difficult problem and few if any open beat detection libraries exist for Swift projects. My hope is that with improvement, Tempi will serve as the go-to solution for developers wanting to add beat detection to their apps. While the focus is currently on real-time beat detection, it can analyze music files too.

Tempi in its current state is "pretty good". It does very well with rock/pop/electronic music where there's a prominent back beat to measure the tempo by. However it needs help with:

- Syncopated music
- Acoustic music
- Music in 3/4 or 6/8 (and other non-4/4 meters for that matter)
- Music with prominent vocals

<b>Why Swift and not Objective-C?</b>


Swift is actually an excellent choice for audio-centric projects. Apple has clearly rewritten or at least largely optimized large parts of the AVFoundation runtime for Swift. For example, while the equivalent version of this project running in Objective-C always maxes the CPU at 100%, the Swift version takes only about 14%. Additionally, Swift arrays are natively compatible with Apple's ```Accelerate.framework``` which provides massive performance gains when manipulating audio samples and FFT magnitudes. On the other hand, much of Apple's audio API is old and C-like making it difficult to work with from Swift. I've tried to abstract that away into the ```TempiAudioInput``` class as much as possible.

<b>Usage</b>


Using the ```TempiBeatDetector``` class in your project is simple and I've included a sample iPhone app to play with.

![iPhone App](https://github.com/jscalo/TempiBeatDetection/blob/master/images/iphone-app.png "iPhone App")


<b>Validation</b>

A robust validation system is critical to evaluating changes made to the beat detection algorithm. The project utilizes Xcode's unit testing infrastructure to perform validation, so just type Command-U to start it. The project includes sample audio files in the 'Test Media' directory which are typically 15-20s in length and categorized into Home, Studio, Threes, and Utility. Here are the current validation results:

- Home set: 54.1%
- Studio set: 69.7%
- Threes set: 36.6%
- Utility set: 100%

While validating, the beat detector can write out plot data which can be really useful when trying to troubleshoot problems or just to understand how it works. When the ```savePlotData``` property is set, data files for each test are saved to the 'Peak detection plots' directory. The plotData file contains time stamps and magnitudes while the plotMarkers file contains time stamps and a marker for each detected peak.

I use the free Mac app [Abscissa](http://rbruehl.macbay.de) to visualize the plots. E.g.:

![Learn to Fly Plot](https://github.com/jscalo/TempiBeatDetection/blob/master/images/learn-to-fly-plot.png "Learn to Fly Plot")


<b>To-do</b>

- <b>Accuracy improvements!</b>
 - Try using a convolution filter
 - Neural networks (I did a lot of work in this area already with mixed results. Email me for more info.)
 - Work on 3/4, 6/8, etc
- Add support for analyzing arbitrary streams of audio samples
- More tests
- Evaluate (and improve, if necessary) impact on battery life

<b>Making Changes</b>

Submit a pull request and I'll review and merge the changes. Changes to the algorithm should result in substantial improvements to validation accuracy.

<b>How do you pronounce Tempi?</b>

TEMP-ee.

## Contact

Contact me via email - s c a l o @ m a c . c o m , or on Twitter - [@scalo](https://twitter.com/intent/user?screen_name=scalo)
## License

MIT License

Copyright (c) 2016 John Scalo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
