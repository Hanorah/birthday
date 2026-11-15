# Assets still required

The current people are PLACEHOLDER figures generated in code. They are NOT the final look.
Real-looking characters must come from a character pipeline:

| Asset | Format | Where it goes |
|---|---|---|
| Protagonist — child, teen, young adult, adult, survivor (rigged, same face) | .glb, humanoid skeleton | assets/characters/protagonist/protagonist_child.glb, ..._teen.glb, ..._young_adult.glb, ..._adult.glb, ..._survivor.glb |
| Girlfriend (from her photo) | .glb | assets/characters/girlfriend/girlfriend_adult.glb |
| Mum, Dad, sister, grandma, uncle | .glb | assets/characters/<id>/<id>_adult.glb |
| Animations in each GLB's AnimationPlayer | named: idle, walk, run, jump, crouch_idle, crouch_walk, climb, sit | (inside the GLB) |
| Voice lines | .ogg | audio/voice/<line_id>.ogg (ids in narrative/dialogue_ch1.json) |
| Final music | .ogg | audio/music/childhood.ogg, menu.ogg, radio.ogg |

Photo-based likeness options: Reallusion Character Creator 4 + Headshot 2 (photo → realistic head, exports rigged FBX/GLB),
or Unreal Engine 5 MetaHuman (most realistic, but MetaHumans may only be used in Unreal Engine).
