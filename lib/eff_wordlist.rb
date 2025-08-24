# EFF's Short Wordlist for Passphrases
#
# Module providing a compact, human‑memorable passphrase generator based on
# the EFF short wordlist. Intended for generating privacy‑preserving login
# identifiers that are easy to remember and type.
#
# Source: https://www.eff.org/dice
#
# Usage examples
# @example Default 7‑word passphrase
#   EffWordlist.generate_passphrase
#   #=> "acid-acorn-acre-acts-afar-agent-algae"
#
# @example Custom word count
#   EffWordlist.generate_passphrase(5)
#   #=> "piper-fjord-iris-brim-gable"
#
# Notes
# - Uses Ruby's PRNG for sampling; not suitable for cryptographic keys.
# - Output is a single string of `word_count` words joined by hyphens.
#
module EffWordlist
  # @!constant WORDS
  #   The EFF short wordlist used for passphrase generation.
  #   Kept in-memory and sampled uniformly at random.
  #   @return [Array<String>]
  WORDS = %w[
    acid acorn acre acts afar agent alarm algae alien alike alive allow aloft
    alone amend angry apart apex apple apply arena argue arise armed armor army
    aroma arrow ascot ashen ashes atlas atom attic audio audit augur aunt aura
    auto awake award aware awful axis bacon badge bagel baggy baked baker balmy
    banjo barge barn baron basic basil batch beach beans beast belly bench berry
    beta bias bike bingo birch birth black blade blank blast blaze bleak blend
    bless blind blink bliss blitz bloat block bloom blot blown blues blunt blurt
    blush board boast boat body bogey boil bold bolt bomb boost booth boots boss
    both boxer brain brand brass brave bread break breed brick bride brief bring
    brink brisk broad broil broke brook broom broth brown brush buddy budge build
    built bulky bunch bunny burst bush bushy butter buyer buzzy cable cache cadet
    cage cake calm camel canal candy cane canon cape card cargo carol carry carve
    case cash casino cast cat catch cater cause cedar chain chair chalk champ
    chant chaos chard charm chart chase cheap check cheek cheer chef chess chest
    chew chief child chili chill chimp chips chive choir chomp chop chose chrome
    chunk churn cider cinch circa civic civil clad claim clamp clap clash clasp
    class clean clear cleat cleft clerk click cliff climb cling cloak clock clone
    close cloth cloud clown club clue clump coach coast coat cobra cocoa code
    coffee coil cold colon color comb comic comma cool coral cork corn cost couch
    cough could count coupe court cover cozy craft crane crank crash crate crave
    crazy creak cream creek creep creme crepe crest crew crisp croak crock crop
    cross crowd crown crude crumb crush crust cub cube cuff cult curb cure curl
    curry curve curvy cushy cycle dab dad daily dairy daisy dance dandy danger
    dark darts dash data dawn deaf deal dean dear death debit debug debut decal
    decay deck decor decoy decree deep deer deity delay delta delve demon denim
    dense depot depth derby desk dial diary dice diet digit dill dime dimly diner
    dingy diode dirt disco ditch ditto diver dizzy dock dodge doing doll dolly
    donor doom door dope dose dot doubt dough down dowry dozen draft drain drake
    drama drank drape drawl drawn dread dream dress dried drier drift drill drink
    drive droit droll drone drool droop drop drove drown drum drunk dry dual duck
    duct dude dug duke dully duly dump dune dunk dupe dust duty dwarf dwell eagle
    early earth easel east eaten eater ebony echo edge eel eerie egg ego eight
    elbow elder elf elk elm elope elude elves email ember emcee emit empty emu
    enable enjoy enter entry envoy epoch equal error erupt essay ether ethic evade
    even evict evil evoke exact exams excel exert exile exist exit exotic expand
    expel export expose extra extol eyed fable faced fact fade faint fair fake
    fall false fame fancy fang far farm fatal fate fatty fault favor fawn feast
    feat feed feel felt femur fence fend ferry fetal fetch fever fiber field fiery
    fifth fifty fight film filth final finch finer first fish five flack flag
    flail flair flak flame flank flap flash flask flat flaw fled flee flesh flew
    flick flier fling flint flip flirt float flock flood floor flora floss flour
    flow flown flub fluff fluid fluke flung flunk flush flute flux foamy focal
    focus fold folk font food fool foot coral force forge forgo fork form fort
    forth forty forum found fox foyer frail frame frank fraud freak free fresh
    friar fried frill frisk from front frost froth frown froze fruit fry fuel full
    fully fungi funny fur furry fury fuse fuzzy gag gaily gain gala game gamma
    gap garb gas gash gate gather gauge gave gawk gaze gear gecko geeky gem gene
    genre geo germ get ghost giant gift gig gills given giver glad gland glare
    glass glaze gleam glean glide glint gloat globe gloom gloss glove glow glue
    goal goat gold golf gone gong good goose gorge gory gosh gouge gown grab grace
    grade grain grand grant grape graph grasp grass grave gravy gray graze great
    greed green greet grew grid grief grill grip grit groan groom grope gross
    group grove grow growl grub grunt guard guess guest guide guild guilt guinea
    guise gulf gulp gummy guru gush gut guy gypsy habit hack half hall halt ham
    hamlet hand handy hang happy hard hardy hare harm harsh haste hasty hatch
    hate haunt haven hawk hay hazard hazy head heady heal heap hear heart heat
    heave heavy hedge hefty helix help hence henna henry herb herd here hero hers
    heyday hid hide high hike hill hilly hilt himself hind hint hip hire hit
    hive hoagie hoard hobby hockey hoist hold holly home honey hood hook hop hope
    horn hose host hot hotel hound hour house hub hue hug hull human humid humor
    hump hung hunk hunt hurdle hurry hurt husband hush hut hybrid hymn ice icing
    icon icy idea ideal idiom idiot idol if igloo ignite ill image imam imbue
    impact import impure inch income index infant info inhale injury inked inlay
    inner input insect inside insist insult intact intake intend inter into invade
    invent invest invite invoice ion iota iris iron island issue itch item ivory
    ivy jab jack jade jag jail jam jar jargon jaw jazz jean jelly jet jewel jig
    job jock join joke jolly jolt jostle joy judge juice juicy july jumbo jump
    jumpy junco jungle junior junk juror jury just keep keg kelp kept kernel
    kettle key kick kidney kind king kinky kiosk kiss kit kite kitty kiwi knee
    kneel knew knife knight knit knob knock knot know koala kung ladle lady lair
    lake lamp lance land lane lap lapel large lash lasso last latch late lather
    laugh launch lava law lawn lawyer lay layer lazy leader leaf leak lean leap
    learn lease leash least leave ledge leech left leg legal lemon lend length
    lens lent leotard less let letter level lever lid life lift light like lily
    limb lime limit limp line linen liner lingo link lint lion lip liquid list
    listen liter liver lizard llama load loaf loan lobby lobe local lock lodge
    loft logic logo loin lone long look loop loopy loose lord lose lost lotus
    loud lounge love lover low lower loyal lucid lucky luge lull lulu lumber lunar
    lunch lung lurch lure lurk lush lute luxury lying lyric mace macro madam made
    magma maid mail main major make makeup male mall malt mama mambo mamma man
    mane mango manor many map maple march mare margin marine mark market marry
    marsh mascot mask mason mass match mate math mating matrix matter maul maybe
    mayor maze meal mean meant meat medal media medic meet meld melee melon melt
    member memo memoir men mend menace menu merge merit merry mesh mess metal
    meter metro mice midst might mild mile milk mill mime mimic mind miner mini
    minor mint minus mirror mirth miser miss mist mite mitt mixer moat mobile
    mocha mock model modem moist mold mole mom moment money monk month moody moon
    mop moral more morn morph mortar most moth mother motion motor motto mount
    mouse mousy mouth move movie mower much mud mug mulch mule multi mummy munch
    mural murky muse music musky must mute myself myth nacho nag nail name nanny
    nap narrow nasal nasty nature naval navy near neat neck need needle negate
    neigh neon nephew nerve nest net neural never new newt next nice niche nick
    night nine ninety ninth noble nobody nod noise nomad noodle noon norm normal
    north nose notch note noun nourish novel now nozzle nude numb nurse nut nutty
    nylon oak oasis oat ocean occur ocean odd odds odor of off offer often oil
    okay old olive omega omen omit once one onion online only onset onto open
    opera optic opus orange orbit orchid order organ other otter ouch ought ounce
    outer outfit oval oven over overt owe owl own ox pace pack pact pad page paid
    pail pain paint pair pal palace pale palm panda pander panel panic pansy
    pants paper parade parent park parrot party pass past pasta paste patch path
    patio patsy patty pause pave paver paws pay peace peach peak peanut pearl
    pecan pedal peek peel peer peg pellet pen pencil penny perch perky permit
    peruse pest petal petite petty phase phone photo piano pick pickle picture
    piece pier pike pill pilot pinch pine ping pink pint pipe piper pitch pivot
    pixel pizza place plaid plain plan plank plant plasma plate play plaza plea
    pleat pledge plenty plight plot plow ploy pluck plug plum plume plump plunge
    plush plus poach pod poem poet pogo point poise poke polar pole police pond
    pony pool poor pop poppy porch pork port pose poser post potion potter pouch
    pound pour power prank pray prefer prefix prep press pretty price pride prime
    print prior prism prison privy prize probe profit prong proof props prude
    prune pry pub public puck puddle puff pull pulp pulse puma pump punch punk
    pupil puppy purple purse push pushy put putt puzzle pyramid quack quail quake
    qualm quarry quart quash quasi queen query quest queue quick quiet quill quilt
    quirk quit quota quote rabbit race racism rack radar radio raft rage raid rail
    rain raise rake rally ramp ranch random range rank rapid rare rash rate ratio
    rave raven reach react read ready real realm reap rear rebel reboot recall
    recap recipe recite record recur red reed reef refer reform refuge refund
    regal regime region reheat reign relax relay relic relief rely remain remark
    remedy remind remix remote remove render renew rent repair repay repeal repeat
    replay reply report repose reprint repute rescue resent reside resist resort
    rest result resume retail retain retina retire retort retro return reuse reveal
    review revise revoke reward rhino rhyme rhythm ribbon rice rich ride ridge
    rifle right rigid rim ripen ripple rise risk ritzy rival river roach road
    roam roar roast robe robin rock rode rodent rogue role roll roof rookie room
    roost root rope rose rosy rotate rotten rouge rough round rouse route rover
    row royal ruby rug rugby ruler rumba rumor run rundown runner runway rupture
    rural rush rust rut saber sadly safe saga sage said sail salad salmon salon
    salsa salt salute salvo same sand sandy sane sash satin satire sauce sauna
    savor savvy scale scalp scan scare scarf scary scene scent school science
    scoff scold scoop scoot scope score scorn scout scowl scrap screen screw
    script scroll scrub scuba scuff sculpt sea seal seam search season seat second
    secret sect sedan seed seek seep segment seize select self sell semi senate
    send senior sense sensor sent septic serene serial series sermon serum serve
    set settle setup seven sever shade shadow shady shaft shake shale shame shank
    shape share shark sharp shawl shed sheep sheer sheet shelf shell shelter sherry
    shield shift shine shiny ship shirt shock shoe shone shook shoot shop shore
    short shot should shout shove shown showy shrank shred shrew shriek shrill
    shrimp shrine shrink shrub shrug shuffle shun shush shut shy siding siege
    sift sigh sight sigma sign silk silly silo silver simmer simple simply sinful
    single sink sip siren sister sit site six size skate sketch ski skid skill
    skim skin skip skirt skull skunk sky slab slack slain slam slang slant slap
    slash slate slaw sled sleek sleep sleet slept slice slick slide slight slime
    slimy sling slip slit sliver slob slog slope sloppy slot slouch slow slug
    slum slump slung slurp slush sly smack small smart smash smear smell smelt
    smile smirk smog smoke smoky smooth smug snack snag snail snake snap snare
    snarl snatch sneak sneer sneeze sniff snip snitch snoop snore snort snout
    snow snowy snub snuff snug so soak soap soar sob soccer social sock soda
    sofa soft soggy soil solar sold sole solid solo solve soma some son sonar
    song sonic soon soot soprano sorry sort soul sound soup sour south soy space
    spade span spare spark speak spear spec speck speed spell spend spent spew
    sphere spice spicy spied spill spilt spine spiny spirit spit spite splash
    splat split spoil spoke spoof spool spoon sport spot spray spread spring
    sprint sprite sprout spruce spry spud spunk spur sput squad square squash
    squat squeak squeal squid stack stadium staff stage stain stair stake stale
    stalk stall stamp stance stand staple star stare stark start stash state
    static statue stay steak steal steam steel steep steer stem step stereo stern
    stew stick sticky stiff still stilt sting stink stint stock stoic stoke
    stomp stone stony stood stool stoop stop store storm story stout stove
    straight strain strand strap straw stray streak stream street stress stretch
    strewn strict stride strike string strip strive strobe strode stroke stroll
    strong strut stuck study stuff stump stung stunk stunt sturdy style suave
    subject submit subset subtle suburb subway such sucker sudden suds suede
    suffice sugar suit sulfur sulk sum summer summit summon sun sunday sunny
    sunset super supply sure surf surge surly survey sushi swab swag swallow
    swamp swan swap swarm sway swear sweat sweep sweet swell swept swift swim
    swine swing swipe swirl swish swoop sword swore sworn swung syrup system
    tab table taboo tacit tacky taco tact tag tail tailor take talent talk tall
    talon tame tan tango tank taper tapir tar tarot tarry task taste tasty tattoo
    taunt tavern tax taxi teach team tear tech teddy teem teen teeth tell temper
    temple tempo tenant tend tender tennis tenor tense tenth term terra terry test
    text thank that thaw the theme theory there these thesis they thick thief
    thigh thing think third this thorn those thread threat three threw thrill
    thrive throat throne throng throw thru thud thumb thump thus tiara tibula
    tick tide tidy tie tier tiger tight tilde tile tilt timber time timid tin
    tingle tip tirade tire tissue titan title toast today toe toff toga together
    toil token told tomato tomb tome tomorrow tone tongs tongue tonic took tool
    toot tooth top topaz topic torch torso tort toss total totem touch tough tour
    tow toward towel tower town toxic toy trace track tract trade trail train
    trait tramp trance trap trash travel tray tread treat treaty tree trek tremor
    trench trend trial tribe trick tricot tried trio trip trite trolley troop
    trophy tropic trot trout truce truck true truly trump trunk trust truth try
    tsunami tub tuba tube tuck tudor tuft tug tuition tulip tummy tumor tuna
    tune tunic tunnel turbo turkey turn turtle tusk tutor tutu tux tweed twelve
    twenty twice twigs twin twirl twist two tycoon tying tyke type typo ugly ulcer
    ultra umpire unable unarm unaware unbend uncle under undue unfair unfit unfold
    unhand unhappy unify union unique unit unity unjust unkind unlit unlock unmet
    unpack unplug unrest unripe unroll unruly unsafe unsaid unseen unset unsure
    untidy untold untrue unused unveil unwary unwell unwind unwire unwish unwrap
    unzip up upbeat update upheld uphill uphold upon upper uproot upshot upside
    uptown upward urban urge urgent usage use user usher usual utmost utter
    vacant vacate vacuum vague vain valid valley valor value van vandal vanilla
    vanish vanity vapor vase vast vault vector vegan veil vein velcro velvet
    vend vendor veneer venom vent venue verb verse versus vessel vest veto
    via vibes vice video view vigil vigor villa vine vinyl violet violin viral
    virus visa visor vista visual vital vivid vocal vodka vogue voice void volt
    volume vomit vote vouch vowel voyage vulgar wade wager wagon waist wait wake
    walk wall wallet walnut walrus wand wander want war warm warn warp warrant
    warrior wart wash wasp waste watch water watery watt wave waver wax way weak
    wealth weapon wear weary weasel web wedge weed week weight weird well went
    west wet whale what wheat wheel when where whey which whiff while whim whine
    whip whirl whisk white who whole whoop whose why wick wide widow width wife
    wifi wild will wilt wimp win wind wine wing wink winner winter wipe wire wiry
    wise wish wisp witch with wok wolf woman womb won wonder wont wood wool word
    work world worm worry worse worst worth would wound wove woven wrap wrath
    wreath wreck wren wrench wrist writ write wrong wrote wrung wry yacht yahoo
    yam yard yarn yawl yawn year yeast yell yelp yes yet yield yodel yoga yoke
    yolk young your youth yoyo yummy zap zeal zebra zen zephyr zero zest zig zinc
    zip zone zoo zoom
  ].freeze

  # Generate a hyphen‑separated passphrase using the EFF wordlist.
  #
  # @param word_count [Integer] number of words to include (default: 7)
  # @return [String] passphrase, e.g. "acid-acorn-acre-acts-afar-agent"
  # @example
  #   EffWordlist.generate_passphrase(3) #=> "mint-robot-gleam"
  def self.generate_passphrase(word_count = 7)
    words = []
    word_count.times do
      words << WORDS.sample
    end
    words.join("-")
  end
end
