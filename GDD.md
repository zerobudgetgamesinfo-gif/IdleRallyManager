# **Game Design Document (GDD): *Idle Rally Manager***

## **1\. Executive Summary**

> * **Genre:** Desktop Companion / Cozy Idle Rally Manager  
> * **Target Platform:** PC (Steam / Native Desktop Application) (Windows, Linux, MacOS)  
> * **Visual Style:** 2D Vector / Illustrated Art (Non-pixel art, cute and cozy aesthetic with animal characters)  
> * **Form Factor:** Docked screen-overlay game running along the bottom or the side of the player's desktop screen while they perform daily tasks/work.  
> * **Core Loop:** Form a team, enter multi-stage rally championships, watch automated side-scrolling rally runs during work hours, make strategic upgrade decisions between stages, and compete solo or asynchronously with friends.

## **2\. Core Gameplay & Structure**

### **Race & Championship Structure**

> * **Championship Model:** Players compete in multi-stage rally championships (e.g., 8 stages total): each stage gives points depending on the results (lowest time wins); at the end of all stages, the player with the most points wins.  
> * Each player has to pick their driver for the championship and their starting car: they have a total budget to spend (for example, 10 points) which they have to use for both (so picking a high-value driver leaves them with fewer points to spend on the car); during stages, events will come up allowing the player to improve both their driver and their car.  
> * **Real-Time Workday Pacing:** Each rally race (stage \+ service park) lasts approximately **1 hour**, matching the natural rhythm of a typical workday shift.  
> * **Hands-Off Racing Mechanics:**  
  * Rally stages are completely **hands-off** once underway—no mid-race pitstops or live interventions are possible.  
  * A stage takes about 30 minutes; the rest of the time is spent at the service park.  
  * During a stage, the car automatically navigates a 2D side-scrolling course featuring occasional jumps, hairpin turns, and environmental scenery.  
  * Each stage has certain requirements for cars/drivers to perform well: one stage might require top speed, another grip on loose surfaces, etc  
> * **The Service Park:**  
  * Between stages, the view transitions to a service park where mechanic characters actively work on the car.  
  * During this phase, players review random upgrade options, stats adjustments, and strategy choices that dictate performance in **subsequent** stages.

### **Characters & Theme**

> * **Cozy Animal Characters:** Drivers, co-drivers, and mechanics are portrayed as charming animals (e.g., cats, dogs, pandas, pigs, monkeys).  
> * **Atmosphere:** Relaxing, low-stress, and companionable—designed to sit unobtrusively on screen as a pleasant workplace buddy.

## **3\. Multiplayer & Community**

> * **Championship Modes:** Playable in **Solo Mode** (against AI bots) or **Multiplayer Mode**.  
> * **Lobby System:** Players can host or join championships using a shared **room code/link**. If a lobby is not fully filled by players, AI bots populate the remaining driver slots.  
> * **Multiplayer Architectures Under Evaluation:**  
  1. *Lightweight Central Server:* Asynchronous cloud-based host maintaining the global schedule and leaderboard regardless of individual player client status.  
  2. *Peer-to-Peer / Steam Networking:* Host-driven session suitable for direct sync via Steam integrations.  
> * For the first version of the game, only single player should be implemented; but future-proofing for multiplayer should be taken into account

## **4\. Technical Architecture (Godot Engine)**

### **Screen-Overlay Setup**

> * **Transparent Borderless Window:** Uses Godot's native per\_pixel\_transparency and borderless mode to float gracefully above taskbars and windows.  
> * **Always-On-Top:** Configured to stay visible without blocking active workflows.  
> * **Click Passthrough:** Defined polygon pass-through areas so mouse clicks pass directly to background work apps.  
> * **Low System Resource Footprint:** Godot’s Low Processor Mode activated to ensure near-zero CPU/GPU strain during background execution.

### **Backend & Tick System**

> * **Interval Tick System:** stage results are computed immediately at the start of the stage, but are not shown to the player: they see the stage evolve over time (this removes the need for all the clients to constantly communicate with one another).  
> * **Data Persistence:** Local JSON or binary save files storing driver profiles, vehicle upgrades, and championship histories.