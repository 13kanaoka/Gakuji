# Gakuji - an SRS Kanji Handwriting App

A spaced repetition flashcard app for learning and practicing how to write the 常用漢字 (jōyō kanji), the 2,136 kanji officially designated for daily use in Japanese. 

Brought to you by **Matthew Rohde** <sub><sup>(Software Development)</sup></sub> and **Vincenzo Escobar** <sub><sup>(Linguistics, Illustrations)</sup></sub>

[→ Setup and Run Guide](#setup-and-run-guide)


## What is SRS?

SRS stands for **Spaced Repetition System**. It is a study method based on the idea that reviewing information at carefully timed intervals helps move it from short-term memory into long-term memory.

The concept is closely connected to the “forgetting curve,” first studied by German psychologist Hermann Ebbinghaus. In practice, SRS is often used with flashcards: items you struggle with appear more often, while items you know well appear less frequently. This makes studying more efficient by focusing your time on the material you are most likely to forget.

## What are Kanji?

Kanji, 漢字, are one of the three main writing systems used in Japanese, along with hiragana and katakana. Kanji originally came to Japan from China in the 5th century and were adapted into the Japanese language over many centuries.

Hiragana and katakana are phonetic scripts, meaning each character represents a sound, but no meaning all on its own. This can be likened to a letter in the latin script such as 'a' or 'b.' Kanji, however, usually represent meaning as well as pronunciation. For example, the word 行く means “to go,” and the kanji 行 carries meaning beyond just its sound. Kanji are also used in names, allowing each name to hold special meaning and unique properties.

Although there are tens of thousands of kanji, the Japanese Ministry of Education designates 2,136 characters as 常用漢字, or “daily-use kanji.” These cover most kanji commonly seen in newspapers, signs, books, official documents, and everyday life. Many adults can recognize more than this, especially depending on their education, reading habits, and personal exposure.

## Why Build This App?

After studying Japanese since 2020 and including a year studying abroad in Japan, we noticed a gap in the resources available for learners who want to practice writing kanji.

In the digital age, many people rely on computers and phones to convert typed kana into kanji automatically with a system called 自動変換 (jidōhenkan). As a result, even native speakers may sometimes forget how to write certain characters by hand, even if they can still read and recognize them without issue.

For Japanese learners, this creates an even bigger challenge. Many learners choose to focus only on reading kanji and skip handwriting altogether, as the return on investment may seem low at first glance. While this can be practical, it can also create gaps in understanding. Without writing practice, it becomes harder to notice how characters are built, how components relate to each other, and why certain kanji look the way they do.

We built this app to help learners practice writing kanji in a structured, consistent, and efficient way. By combining handwriting practice with spaced repetition, the goal is to make kanji study more active, memorable, and connected to long-term understanding.

# Setup and Run Guide
### Mac
**Setup**  
1) Install Flutter SDK [here](https://docs.flutter.dev/install) (if you don't already have it)  
2) Clone the repository and install dependencies:  
```  
git clone git@github.com:13kanaoka/Gakuji.git
cd Gakuji
flutter pub get
```   
3) Download `dictionary.db` from the [Releases page](https://github.com/13kanaoka/Gakuji/releases/tag/assets-dictionary) and place it at:  
```
assets/dictionary/dictionary.db
```  
4) Install Xcode to your computer through the App Store on Mac. Then, in the terminal, run:
```
sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
```
5) Accept the license:
```
sudo xcodebuild -license
```
6) Download iOS platform / simulator support
```
xcodebuild -downloadPlatform iOS
```
7) Check for validity
```
flutter doctor -v
```  
  
**Run**
1) While navigated to your project directory, run:
```
open -a simulator
```
2) Then, run the following command. replace {device name} with whatever simulator you end up using.
```
flutter run -d '{device name}'
```

### Windows (coming shortly)
