# Making the real-looking characters (Avaturn + Mixamo, free)

## 1. Create him in Avaturn
1. Go to avaturn.me and sign up (free).
2. Choose "Create avatar from photos" and upload 3 clear photos of him:
   front, left and right. Use even light and no filters. The purple-lit Snapchat photo
   will make the skin tone wrong, so use natural daylight photos.
3. Adjust: hairstyle (locs/twists), beard, body shape, outfit.
4. Export as GLB. Save it as:
   assets/characters/protagonist/protagonist_adult.glb
   Make a second export with a fuller beard and worn clothes as protagonist_survivor.glb

## 2. Her and the family
Same steps, from their photos:
- assets/characters/girlfriend/girlfriend_adult.glb
- assets/characters/mum/mum_adult.glb, dad/dad_adult.glb, grandma/grandma_adult.glb ...

## 3. Animations (Mixamo, free)
1. mixamo.com: upload the Avaturn GLB, then download these as FBX "Without Skin":
   Idle, Walking, Running, Jump, Crouched Walking, Climbing Ladder, Sitting.
2. Put them in animations/mixamo/. Claude wires them to the characters.

## Limits to know
- Avaturn makes adult bodies only. The baby, child and teen versions of him
  need another source or a stylised stand-in.
- Avaturn is realistic game-character quality, not film-photoreal.
