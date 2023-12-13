# Atari Missile Memorizer

An original Atari 2600 (Atari VCS) game. Created as my final project for CSE 337 - Retro Game Design (Fall 2023) at Washington University in St. Louis.

This is a simple memory game (like the classic game "Simon").

Various portions of the code were taken/adapted from examples provided in class by the instructor, such as the random-number generation code, and code that must be present in all Atari games in order for them to run correctly.

## Setup

1. Install Stella (https://stella-emu.github.io/) Atari 2600 Emulator
2. Clone this repository, or just download `game.bin`
3. Open `game.bin` in Stella

## Controls
* **Joystick Up/Down**: Move player up/down
* **Joystick Left/Right**: Move player left/right
* **Joystick Button**: Fire missile

## How to Play
 1. Press the Reset button to begin the game
    - F2 by default on Stella
 2. Watch and memorize the sequence of targets that light up green
    - Unable to move during this phase
    - Writing the sequence down is cheating
 3. Once the sequence is done playing, move the player and fire missiles at the same sequence of targets
 4. If successful, the next level will begin, and one target will be added to the end of the sequence
 5. If an incorrect target is shot, it will light up red, and the game will return to the first level with a new sequence
 6. Aim to get to the highest level possible
    - Level 19 is the highest that won't break the game

## Compiling the Game (Advanced)
1. Install dasm (https://dasm-assembler.github.io/) and Stella (https://stella-emu.github.io/).
2. Clone this repository
3. Create a new directory inside the repository called `includes`
4. Download the following two files and put them in that directory:
    1. https://raw.githubusercontent.com/dasm-assembler/dasm/master/machines/atari2600/vcs.h
    2. https://raw.githubusercontent.com/dasm-assembler/dasm/master/machines/atari2600/macro.h
5. You are able to modify `game.asm` at this point if you want to modify the game code
6. Compile with the following command (make sure `dasm` is in your PATH):
```
dasm game.asm -Iincludes -ogame.bin -sgame.sym -lgame.lst -f3
```
7. Open `game.bin` in Stella