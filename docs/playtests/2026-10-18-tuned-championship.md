# 2026-10-18 — tuned championship

Clocked with the championship rules at `time_scale` 30 (24 seeds, every legal starter pair, three ways of picking cards) and one service window stepped at `time_scale` 1. The service length at scale 1 is 1800 seconds, half an hour.

## Starter catalog

Bramble + Mudbug was the draft. It was the only pair that won, and it won on stage 1 before any card. Pip + Teapot finished last on points (about 15) and never won. Best and worst card picks flipped the title 0 times in 96 paired runs. Every rival took the same card in every service, and the AI order was mostly Bramble, then the middle, then Pip. Stage 8 changed the champion once in 48 runs. Later services dropped the safe card once it had been owned, so the offer shrank to two cards.

## What changed in the data

Stat peaks came down so a specialist and a spare-parts pair sit nearer each other. Stage weights now give snow a reliability bias and the finale a jump bias, instead of grip winning three stages. A second general card per stat is `+2`, and a second safe card per stat covers the stat when it is top again. An owned safe card falls through to that second card. A general card that would push a stat past three raises stays out of the pool.

## Tuned loop

Kiko + Teapot won 5 of 24 seeds when the player took the best card for the next stage. Pudding + Wagon, Pudding + Teapot, Bramble + Teapot, and Kiko + Wagon also won. Pip + Teapot averaged 33 points and won none; it does not beat the specialists. Spending the whole budget is no longer required, and it is no longer free points either.

On the first service of seed 4 (Kiko + Wagon, next stage Coastal Tarmac) the three cards were not the same effect: Shorten the gearing (`pace_2`) took 6.9 seconds off the next stage, Tighten the shifts took 3.9, and Soft compound took 0.9. Always taking the safe `+1` dropped Kiko + Teapot from 42 points to 31, and that pair's wins went from 5 to 0, because the rivals take the `+2` when it is drawn. The half-hour default is a real loss, not a label change.

One full run at scale 30, Bramble + Dart, seed 4, picking the best offered card: Pudding + Wagon won with 50 points, the player finished 7th on 30. Across seeds the AI order differed 22 times out of 24, and five different rivals won while the player was Pip + Teapot. Stage 8 took the title off the overnight leader in 19 of 48 runs, so the last stage still matters. The workday is still eight stages; it did not feel short at this scale. Seven services each offered a different set of three cards, including a safe card after the first copy was owned.

Temperament is a line on the driver and shows on the final table. It is not in the solve.

## Verdict

A full championship is worth playing. Career starts from here: reputation is the points total, banked when the final table is dismissed.
