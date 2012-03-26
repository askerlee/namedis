package ConceptNet;

use feature qw(switch say);

use strict;
use warnings 'all';
use lib '/media/tough/namedis';
#use lib 'd:/shaohua/namedis';

use NLPUtil;
use List::Util qw(min max sum first);
use List::MoreUtils qw(first_index);
use Devel::Peek;
use Term::ReadLine;

# used in dfsExpandAncestors() to cut off branches where their depth changes too drasticly
our $MAX_ANCESTOR_DEPTH_DIFF		= 1;
# minimal depth (from root) of an ancestor to make it worth considering
our $MIN_ANCESTOR_DEPTH				= 2;
# used in expNormalizeArray(). not used now
our $KEEP_MATCH_TOP_N_RESULTS 		= 10;

# whether to use information content when calculating term closeness
our $CALC_SIMI_USE_IC				= 1;
# the frequency (matching score) passes up with attenuation. 
# i.e. the nearer to root, the less score an ancestor term gets
our $USE_FREQ_PASSUP_ATTENUATION	= 1;

# the least score of a matched term for it to be counted in trainDBLPFile() & adFreqAndAuthors()
our $LEAST_COUNTABLE_MATCH_SCORE = 0.15;

# queries with results more than this value are considered containing no information
our $TOKEN_MAX_MATCH_TERMS			= 800;
our $MATCH_TERM_WINDOW 				= 4;
#	EXT_TERM_DISCOUNT 				= 1/3;
our $CUTOFF_OF_BEST_MATCH			= 0.3;
our $INVERSION_DISCOUNT  			= 0.3;
our $SKIP_TOKEN_EQ_INVERSION 		= 0.6;
our $SKIP_QUERY_TOKEN_DISCOUNT		= 0.5;
our $CONTEXT_MATCH_DISCOUNT			= 0.5;
our $UNMATCHED_STOPWORD_DISCOUNT	= 0.7;
our $DIFF_SUFFIX_DISCOUNT			= 0.6;
our $DIFF_SUFFIX_1_TOKEN_DISCOUNT	= 0.4;
our $MIN_VALID_1_QUERY_TOKEN_TFIAF	= 1;
our $DEFAULT_TERM_MATCH_WEIGHT_THRES	= 0.2;
our $MATCH_LEAST_FREQ_AFTER_ENTROPY_DISCOUNT	= 0.05;
our $NORMALIZE_EXP_COEFF			= 2;
our $MATCH_SET_SIZE_CACHE_THRES		= 3;
our $MATCH_UNKNOWN_TOKEN_WEIGHT		= 4;
our $MATCH_1_OF_N_TOKENS_DISCOUNT	= 0.4;
our $MATCH_1_MISS_CONTEXT_DISCOUNT	= 0.6;
our $MATCH_MISS_TOKEN_PUNISHMENT	= 3;
our $MAX_WEIGHT_COV_BY_PERFECT_MATCH	= 0.5;

our $CACHE_MATCH_SET = 1;
our $CACHE_BIGRAM_POSTING_LEAST_FREQ	= 8;

our $MAX_STOPWORD_GAP_NUM_IN_QUERY		= 1;
our $MAX_STOPWORD_GAP_WEIGHT_IN_QUERY	= 1.5;
our $DISABLE_1_TOKEN_QUERY_PARTIAL_MATCH	= 1;
our $DISABLE_1_TOKEN_DIFF_SUFFIX_MATCH		= 1;
our $MATCH_1_TOKEN_QUERY_DISCOUNT	= 0.7;
our $MATCH_1_TOKEN_QUERY_TO_TERM_WITH_CONTEXT_DISCOUNT = 0.7;

our $SUSPICIOUS_INHERIT_DEPTH		= 10;
our $SUSPICIOUS_INHERIT_DEPTH_RATIO	= 2;
our $MAX_TRAIN_TITLE_NUM 			= 10000000;

our $CONCEPT_VEC_TOP_N_TO_CLUST_SIZE_RATIO 	= 3;
our $CONCEPT_VEC_LEAST_TOP_N		= 20;
our $CONCEPT_VEC_MOST_TOP_N			= 100;
our $MAX_LEAST_DEPTH_FOR_COMMON_ANCESTOR	= 3;
our $GENERALIZATION_DISCOUNT_PER_STEP	= 0.7;

our $YEAR_TOLERANCE = 2;
our $YEARLY_ATTENUATE = 0.7;
our $MAX_YEAR_DIFF = 6;

our $USE_VEC_SIMI_LOWER_BOUND		= 1;

our $MERGE_NEARBY_TERMS_IN_MATCH_RESULT	= 1;

use enum qw(BITMASK:DBG_  CONCEPT_NET_FIRST=1024
						  CALC_MATCH_WEIGHT MATCH_TITLE TRAVERSE_NET TRAVERSE_NET_LOW_OP
						  TRACK_ADD_FREQ ADD_EDGE CHECK_ROOT_ANCESTOR LOAD_ANCESTORS CALC_IC
						  LOAD_IC CHECK_INHERIT_DEPTH_RATIO CALC_SIMI BUILD_INDEX CALC_TOKEN_ENTROPY
						  INIT_LISTS
						  
			);

our %sizeof;
our @conceptNet;
our @revConceptNet;

our @terms = ("CONCEPT_NET_ROOT");
our @termTokens = ( [ "CONCEPT_NET_ROOT" ] );
# @{$termTokens[$i]} excluding the context part. 
# i.e.: @{$termTokens[$i]}[ 0 .. $termContextStart[$i] - 1]
our @termMainTokens = ( [ "CONCEPT_NET_ROOT" ] );
our @termContextStart = ( 1 );

our $conceptNetRootLemma = lemmatize('CONCEPT_NET_ROOT');
our %termLemmaTable = ( $conceptNetRootLemma => 0 );
our %invTable = ( CONCEPT_NET_ROOT => [ ] );
our $termGID = 1;

our @freqs;
our @ICs;
# in each cell, it is the sum of the term's own original freq & it's children's original freqs
# "gen1" means 1-level generalization. 1-level gen, because in @term2authorIDs we tolerate 1-level gen
# it's summed up in addFreqAndAuthors(), as @freqs 
our @gen1freqs;
# the sum of all concepts' original frequencies (not counting in the propagated freqs)
our $MC = 0;
our $addedFreqSum = 0;
our $addedCountableFreqCount = 0;
our $avgMatchScore;

our $ICOffset = 0;

our $lastCalcMC = 0;

# an array of hash refs
our @term2authorIDs;
# the counts of keys (author IDs) in the above hash refs
our @termAuthorCount;

our %authorName2id = ();
our @authors = ();
our $authorGID = 0;

our %commonTokens;

our @edgeTable = ( {} );
our @edgeTableNC = ( {} );

# useless. wikipedia concept network is always cyclic
our $isCyclic;

our @dfsTree;
our @dfsHashTree;
our @bfsTree;
our @bfsHashTree;
our @subtree;

our @ancestorTree;
our @inheritCount;
our @depthByBatch;
our @attenuateByBatch;
# reciprocals of above array. to improve efficiency (change division to multiplication)
our @recAttenuateByBatch;

our @bfsDepth;

our @visited;
our %excluded;

our %matchSetCache;
our $matchSetCacheHitCount = 0;

our %highFreqBigrams;
$NLPUtil::nameof{\%highFreqBigrams} = "%highFreqBigrams";

our %postingCache;
our $postingCacheHitCount = 0;

our %gramEnt;

use enum qw(:NEWTERM_ SIMPLE COMPLEX);
our $newTermMode = NEWTERM_SIMPLE;

sub setNewTermMode($)
{
	$newTermMode = $_[0];
	my $modeStr = "UNKNOWN_MODE";
	given($newTermMode){
		when(NEWTERM_SIMPLE){
			$modeStr = "NEWTERM_SIMPLE";
		}
		when(NEWTERM_COMPLEX){
			$modeStr = "NEWTERM_COMPLEX";
		}
	}
	print STDERR "new term mode is set to $modeStr\n";
}

our %nameof = (\@conceptNet => '@conceptNet', \@subtree => '@subtree', \@ICs => '@ICs');

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(@conceptNet @revConceptNet @terms @ICs
				@ancestorTree @inheritCount
				@dfsTree @bfsTree @subtree
				$termGID @visited
				@excluded %excluded @excludedX %excludedX $isCyclic %whitelist %whiteEdge %blackEdge
				%stopterm @stopped
				%similarVenues

				normalizeArray expNormalizeArray calcInvNum0 calcMisalignment checkHyphenedTokens
				push2 pop2 shift2 unshift2 NO_OP bitmap2nums entropy calcTokenEntropy 

				cmdline setNewTermMode iniReliantLemmas setICOffset initPostingCache fetchPostingCache

				getTermID getTermIC terms2IDs
				addEdge addEdgeByID doesEdgeExist doesEdgeExistNoCase doesEdgeExistByID
				isExcluded isExcludedX isStopTerm isBlackEdge hasIllegalChar cleanTerm buildIndex
				matchPhrase matchTitle calcMatchScore recordBestMatches addMatchScores distributeMatches
				unigramMatchTitle
				calcNetIC saveNetIC loadNetIC trainDBLPFile addFreqAndAuthors addFreqs
				calcConceptVectorSimi calcTitleSetSimi calcTermCloseness mergeNearbyTerms
				compactConceptVector titleSetToVector emptyConceptVecSimiCache
				dumpConceptVec dumpConceptVenueVec dumpTitleset dumpSimiTuple
				updateYearRange removeOverlapTerms
				
				dfsPostorder breadthFirst dfsPreorder dfsRemoveCycle bfsExhaustAncestors
				leastCommonSubsumer
				exclude exclude4whitelist include excludeX addStopterm
				dumpChildren dumpAncestors listUniqueChildren setTopAncestors enumAncestors
				saveAncestors loadAncestors
				);
#				checkCycle

$| = 1;

our ($excluded, $excludedX, @excluded, @excludedX, %excludedX, %whitelist,
		$stopterm, %stopterm, @stopped, %whiteEdge, %blackEdge, $reliantLemmas, %reliantLemmas, );

sub setICOffset($)
{
	print $tee "Set \$ICOffset: $ICOffset => $_[0]\n";
	$ICOffset = $_[0];
}

sub iniLists
{
	$excluded = 'Actuarial science, Fictional robots, Audio engineers,
				Electronics companies, Optical illusions, Digital radio,
				Telecommunications equipment vendors, Networking companies,
				Thermodynamics, Computing by computer model, Statistical data types,
				Fields of application of statistics, Internet slang, Internet by country,
				Consumer electronics brands, Satellite radio, Types of scientific fallacy,
				Mathematics literature, Television technology, Numbers, Consumer electronics,
				Application software, Network-related software, Electronic publishing,
				Software, Scientific modeling, Videotelephony, Mathematicians,
				Websites, Light guns, Artificial intelligence in fiction, Electronic literature,
				History of cryptography, Online education, News websites, Computer magazines,
				Single-board computers, Sound recording, Internet governance, Military communications,
				History of mathematics, Scientific method, Microwave technology, Radar,
				Seduction community, Philosophy of mathematics, Internet privacy,
				Information technology organisations, Electrodynamics, Electronics standards,
				Management science, Backward compatible video game consoles, Computer storage media,
				Video game development, Information appliances, Digital television,
				Power Architecture, Film and video technology, Audio storage, Video storage,
				Blu-ray Disc, Avionics, Online auction websites, Video on demand services,
				Mathematical notation, Mathematics and culture, Wireless networking,
				Digital art, Facebook, Articles with example code, Internet companies,
				Simulation software, Personal documents, Graphic design, Vision,
				Web applications, Recording, Video games with 3D graphics,
				Software companies, History of telecommunications, Streamy Awards,
				Chess openings, Dimensional analysis, Digital libraries,
				Psychology books, Battery %28electricity%29, Graphology,
				Electronic component distributors, Web Map Services, Calculators,
				Filename extensions, Telecommunications by country, Rockets and missiles,
				Torpedoes, Yahoo!, Organizations in cryptography, internet television,
				Internet television series, one laptop per child, cellular automatists,
				model theorists, theoretical computer scientists, lattice theorists,
				game theorists, roboticists, combinatorial game theorists,
				lists of telescopes, lists of mathematicians, lists of things named after mathematicians,
				freedom of information activists, russell\'s paradox,
				Economic data, Driving licences, Emergent gameplay, Biocybernetics,
				Video games by graphical style, Phylogenetics, Home computers, 3-D films,
				Internet personalities, Computer-animated films, Computer-animated television series,
				X86 emulators, Internet memes, Time travel, Units of volume,
				People in information technology, Businesspeople in the telecommunications industry,
				Broadcasting, Businesspeople in computing, Dot-com, Point of sale companies,
				Audio transducers, Science fiction fandom, DNA, Interactive fiction,
				Internet activism, Optical computer storage, Personal computers, Virtual reality in fiction,
				Government databases, Interferometry, New media, Laserdisc, Biopunk,
				Computational chemistry, Library of Congress Classification, Mathematics competitions,
				Clinical research, History of calculus, Ethics and statistics, Filters,
				Animal communication, Joint Electronics Type Designation System, Fireworks,
				Mecha, Electrical generators, Vacuum tubes, History of computing, Photography,
				Internet Assigned Numbers Authority, Celestial navigation, Communication design,
				Romanization, British Computer Society, Space probes, Charge carriers, Nonprofit technology,
				Cloud computing vendors, Dreaming, Video games with stereoscopic 3D graphics,
				Computer viruses, Writing, Travel and holiday companies, Systems biology, Censorship,
				Superstitions, Pseudoscience, Psychological warfare,
				Names, Recorded music, Taxonomy, Visual arts,
				Internet broadcasting stubs, Aviation, Prevention,
				Timekeeping, Film, Radio stubs, Planning, light, effects units, 
				Music, Travel, Geocodes, Currency, Energy policy,
				Optical materials, Temperature, International security,
				Events, Astronomical dynamical systems, Vortices,
				Political theories, Social systems, Flash cartoons,
				Statistical data coding, Demography, Speech and language pathology,
				Oral tradition, Time, Units of measure,
				Vocal music, Fiction, Experimental physics, Risk,
				Habitats, Public speaking, Onomastics, Thermodynamics,
				Quantum mechanics, Continuum mechanics, Seismology,
				Classical mechanics, Relativity, Soil mechanics,
				Biomechanics, Solid mechanics, Experimental mechanics,
				Mechanical vibrations, Oscillation, Mechanical power control,
				Mechanical power transmission, Mathematics of rigidity,
				Crowd psychology, Causality, Qualitative research,
				Consortia, Analysis, Data collection, Radio, Encodings,
				Television, Notation, Writing, Behavior,
				Theoretical physics, Political theories, Economic theories,
				Obsolete scientific theories, Theories of gravitation,
				Chemistry theories, Psychological theories, Hypotheses,
				TRIZ, Sociological theories, Political science theories,
				Geology theories, Ecological theories, Biology theories, Evolution,
				Astrophysics theories, Energy, Mass, Hydrography, Infographics,
				Foreign policy, Policy, Voting, Statistical mechanics, Research,
				Statistical data sets, Classification systems, Prisons,
				Locksmithing, Brands, Strategy, History of mass media,
				Flight, Power %28physics%29, Video game companies,
				Music and video, Photography, History of film, History of television,
				History of radio, History of broadcasting,
				Defunct telecommunications companies of the United States,
				Morse code, Northern Electric, History of mass media, Beacons,
				Telecommunications museums, History of the telephone,
				Military projects, Length, Scientific observation,
				Failure, Explosives, Lighting, Technology by type,
				Theories of deduction, Espionage, Scientific equipment,
				Telecommunications by country, Broadcasting, Television networks,
				Tests, Climate and weather statistics, Information technology companies,
				Sports records and statistics, Interest, Telecommunications companies,
				Statistical organizations, Statisticians, Visual disturbances and blindness,
				Video games by genre, Charts, Enterprise modelling,
				Knowledge management, communications by country,
				Agricultural machinery, Machine manufacturers,
				Lawn and garden tractors, Industrial machinery, Packaging machinery,
				Engines, Telephone numbers, Experimental music, Films by technology,
				Printing, Omics, Music production, Seals %28insignia%29, Java,
				Color, Experimental film, Phonaesthetics, Scale modeling,
				Experimental vehicles, Computing culture, Audio equipment manufacturers,
				Video games, Rockets and missiles, Virtual pets, Digital radio,
				Visualization experts, WikiProject Websites, Logos, Words,
				Words and phrases by language, Lexical semantics, Video game publishers,
				Video games by company, Printmaking, Free wiki software, Wiki communities,
				Free websites, "Home automation", "Machinery", "Heating, ventilating, and air conditioning",
				"Building automation", Microwave technology, Index numbers, Economic indicators,
				Optoelectronics, Quantum electronics, Semiconductor companies, Wikis,
				Books available as e-books, WikiProject Telecommunications,
				Synchrotron-related techniques, Childhood software, Simulation video games,
				Video game software, MPEG, Transport simulation games, Free entertainment software,
				Media players, Adobe Flash, Music software, Video game engines,
				Multiplayer online games, Film and video technology, Computer hardware by company,
				Amiga software, Actuarial science, Linux games, Video game hardware,
				Internet personalities by country, Software for children, Exergames,
				Software companies by country, Internet personalities, Scientific techniques,
				Semiconductor materials, Consumer electronics brands, Sony subsidiaries,
				Websites by country, Video game developers, Internet companies by country,
				Video game templates, Graphic designers, Wikipedia bots, Superlatives,
				History of video games, Albums by cover artist, Astronomical catalogues,
				Blindness, Chess titles, Semiotics, Buildings and structures by shape,
				Sound, Orientation, Waves, Radiation, Electrodynamics,
				Convection, Podcasting, Video game lists, History of mathematics,
				Computer criminals by nationality, Lithography, Wave power,
				Mathematicians by nationality, Cryptographers by nationality, Computer programmers by nationality,
				Computer specialists by nationality, Video game designers,
				Electronic sports, Smartphones, MP3, Audio players, Digital audio,
				IOS (Apple), Celestial coordinate system, Surveillance scandals,
				Adages, Applications of control engineering, Control engineering,
				Lexical units, Biostatistics, Epidemiology, Video game design,
				Wikipedia and mathematics, Educational websites, Typography,
				Electronic games, Interactive television, Citizen media,
				Actuaries, Cyberpunk writers, Pi, Educational video games,
				Cable television, Mathematics education, Mathematics fiction books,
				Electronics work tools, Topologists, Web syndication, Privacy law,
				Sound chips, Web animation, Cryptographers, Android films,
				Automotive electronics, People associated with electricity, Magnetic propulsion devices,
				Electric power by country, Atom, Power stations by country, Astronomical observatories,
				Hydroelectric power stations, Solar power stations, Nuclear power stations,
				Nuclear power by country, Mathematics and culture, Ratio, VoIP companies,
				KDE games, widget management systems, free mathematics software, text editors,
				HTML editors, on line chat, utilitarianism, instant messaging clients,
				list of video telecommunication services and product brands, sulfur,
				computer lists, c software, utility software, software by operating system,
				comparison of pascal and c, SLR cameras, earth forum, differential geometers,
				android (operating system), integrated development environments, category theorists,
				wireless network organizations, electric power transmission in india,
				ASCII art, zeitgeist, PHP, java libraries, free compilers and interpreters,
				signals intelligence, termcap, GNOME, word processors, software by domain,
				widgetbox, public opinion, MSN, linux distributions, debian, DOS on IBM PC compatibles,
				universal mobile telecommunications system mobile phones, second life,
				global internet community, internet exchange points, qt (framework),
				qt (toolkit), package management systems, free operating system technology,
				c headers, system administration, catalog of articles in probability theory,
				bulletin board system software, system software, source code, statistical software,
				web accessibility, computer security companies, musical set theory, audio engineering schools,
				set theory (music), normal mode, netCrunch, wikipedia, dimension, web series,
				online games, solar powered vehicles, tidal power, 

				Wireless carriers, Mobile phones, Computer storage devices by company, Computer art,
				Internet service providers, Computer hardware companies, Home computer software,
				Hacking %28computer security%29, Computer companies, Electronics manufacturing,
				Computer science organizations, Microsoft games, Machinima, Telecommunications law,
				Secret broadcasting, Handheld game consoles, Open source games, IPhone OS software,
				Commerce websites, Sony software, DOS software, Mathematics awards,
				Submarine telecommunications cables, Telecommunications policy,
				Internet in Russia, Information technology by region, Information technology education,
				Windows games, Video game platform emulators, Freeware, Single-platform software,
				Lua software, Computer industry, Online journalism, Databases by country,
				Articles containing proofs, Electronics lists, Recreational cryptographers,
				Internet hoaxes, Internet radio, Twitter, Card game video games, Video art,
				Mathematics organizations, People associated with computer security,
				Electronics and the environment, High-end audio, Communications satellites,
				Cyborgs, Open access journals, Graphing calculators, Electronics engineers,
				Honeywell, Computer books, Sound archives, World Wide Web stubs, Radio terminology,
				Digital cameras, Software engineers, Mac OS software, Graphics hardware companies,
				Current TV, Fabless semiconductor companies, Computer programmers, CPU sockets,
				Credit card rewards programs, Volume, Software cracking, Electronics districts,
				Fellows of the Association for Computing Machinery, Dielectric gases,
				Military radio systems, Equipment semiconductor companies, Digital movie cameras,
				Video board games, Video Board Games, Educational software companies, Statistical awards,
				Computing by company, Infrared sensor materials, Weather satellites,
				Films shot digitally, Cable radio, Chess theoreticians, Cryobiology,
				Types of databases, Warning systems, Unix games, Creative Commons-licensed works,
				ERP software, Guitar effects manufacturing companies, That Guy with the Glasses,
				Gateway/routing/firewall distribution, Internet talkers, Fictional superorganisms,
				Domestic heating, Supercomputer sites, Computer science teachers, Software by operating system,
				Mathematics websites, Database administration tools, Women computer scientists,
				Number theorists, Computer security software, Lens mounts, Earth stations,
				Operations researchers, Geometers, Scientific computing researchers,
				Artificial intelligence researchers, Researchers of artificial life,
				Database researchers, Computer scientists by field of research,
				Programming language researchers, Free media software, Online service providers,
				Bioinformaticians, ASCII, Programming language designers, Formal methods people,
				Graph theorists, Information theorists, Probability theorists, Set theorists,
				Control theorists, Queueing theorists, Dice, Bermuda Triangle,
				Computer network organizations, Semiconductor physicists, Electronics introduced in 1992,
				Massively multiplayer online games, Unix SUS2008 utilities, Computer peripheral companies,
				Operating system distributions bootable from read-only media, Unicode proposals,
				Bandplans, Holography in fiction, Mathematics-related lists, Video games with vector graphics,
				Electronic design automation software, Interest rates, Proteomics, Linux people,
				Hot air engines, Medical ultrasound, Encodings of Japanese, Computer science literature,
				Enterprise modelling experts, Live USB, Econometricians, Review websites, Mainframe games,
				Web humor, Sound cards, Computer storage companies, YouTube, Floppy disk computer storage,
				Hard disk drives, International relations theory, Internet self-classification codes,
				Computer graphics professionals, Unix people, Mozilla, KDE, Artificial intelligence laboratories,
				Negotiable instrument law, Mathematical analysts, Phonologists, Theoretical biologists,
				Survey methodologists, Web hosting, Mail transfer agents, Graphics file formats,
				Computer hardware researchers, Open source network management software,
				Computer file formats, File transfer protocols, Editing software, Video editing software,
				Rootkits, Microphone manufacturers, Mathematical science occupations, Open content films,
				Machine learning researchers, Human-computer interaction researchers,
				Researchers in distributed computing, Computer vision researchers,
				Semiconductor journals, Statistics journals, Radiology journals, New media art,
				Computing comparisons, Free system software, History of the Internet,
				Internet Explorer, Linux User Groups, Unix software, Graphics software, Web designers,
				Netbooks, Employment websites, Online brokerages, Mach, Open content activists,
				Electronic engineering publications, Utilitarians, Metadata, Internet Gopher,
				Film sound production, DOS extenders, Memory management software, Computing websites,
				Early computers, Anthropometry, Archive formats, One-of-a-kind computers, Linux companies,
				Storage software, Disk operating systems, Window-based operating systems,
				Computer terminals, Terminal emulators, BitTorrent clients, Test equipment manufacturers,
				Audio amplifiers, Radio controlled cars, Computer power supply unit manufacturers,
				Light-emitting diode manufacturers, Programming contests, Video games with textual graphics,
				Virtual communities, Installation software, Metal detecting finds,
				Executable file formats, Debuggers, Fare collection systems,
				Motherboard companies, Motherboard form factors, Widget toolkits,
				Films about telepresence, Java platform games, History of Wikipedia,
				Algol programming language family, Chaos theorists, Mac OS X software,
				Rubber, Disambiguation, Hydroelectricity by country, Electric power companies,
				Nuclear power, Power stations by condition, Fossil fuel power stations,
				Electrical engineers, Electrical engineering companies, Wikipedia books on mathematics,
				Coal power, Glassmaking companies, Trolleybus transport, Amtrak, Owned,
				AE Smith, Jumptap, UNESCO, List of fictional robots and androids,
				HVAC manufacturing companies, OS/2 software, BeOS software, Deaths by electrocution,
				Combinatorists, Tetris, Al Gore, Internet vigilantism, Deconstruction,
				Open content films, Warez, Reasoning, Criminal justice, Dot com people,
				Moore School Lectures, Transmitter hunting, Narratology, Energy crops,
				Glass science institutes, Android software, Cryonics, Topography,
				Hydroelectric power companies, WAAS reference stations, Photographic lenses,
				Numerical analysts, Algebraists, Lists of software, Pregap, Mirial s.u.r.l.,
				Mac OS X, Network related software, Clients, FTP, Web Browsers, Coolants,
				Photography equipment, Residential heating, Shareware,
				Customer relationship management software, lens manufacturers,
				lists of computer terms, insulated glazing, battery manufacturers,
				computer memory companies, toy robots, file managers, generation scotland,
				graphing calculator, poker probability (omaha), alumni associations,
				punctuation, garmin, linux software, pascal, free software programmed in assembly,
				free software programmed in PHP, free software programmed in perl,
				free software programmed in fortran, text executive programming language,
				algebraic geometers, keyboard layout, discontinued operating systems,
				torah database, standard unix programs, proprietary software,
				microsoft development tools, user interface builders, vector graphics editors,
				group theorists, web service providers, windows live, toshiba, bing,
				routing software, free application software, home video, baidu,
				bing (search engine), william gibson, crank storyboard suite,
				caller ID, fortumo, mathematical logicians, list of north american broadcast station classes,
				linux conferences, joining, polyvinyl acetate, taskbar, high end audio,
				3D graphics software, c standard library, handheld game console,
				microprocessors by company, game console operating systems, recreational mathematics,
				levitation, fictional characters with electric abilities, proprietary operating systems,
				logic programming researchers, laser medicine, contactless smartcards,
				gene banks, video cards, command shells, robotics middleware, preposition and postposition,
				milewski\'s typology, graphics chips, programming languages by creation date,
				sound laws, col (game), Official statistics, seals (insignia), cryptography publications,
				cryptography books, community networks, united states, metallurgy,
				north america, Tone (linguistics), historical document, accelerator (software),
				language learning software, usenet clients, star ranking systems, space,
				DAB ensemble, USB OTG compatible devices, poetry, numerals, monte carlo methodologists,
				bloggers, internet related lists, laptops, statistics education,
				list of home video companies, IPhone, IRIX, usenet people, syrup,
				navigation system companies, electrical connectors, signal connectors,
				planetaria, glass museums and galleries, inXitu, loudspeaker manufacturers,
				articles with example c code, master tracks pro, the longest suicide note in history,
				blogs, free software, remote administration software, streaming software, computer errors,
				subversion, free groupware, BASIC programming language family, BASIC programming language,
				AOL, aftermarket firmware,
				articles with example python code, articles with example java code,
				articles with example SQL code, articles with example haskell code,
				articles with example scheme code,
				uncracked codes and ciphers, wildcard character, nortel products,
				digital signal processors, erlang (programming language), erlang programming language,
				cryptography law, operator theorists, free revision control software, internet forums,
				software projects, data analysis software, lorentzian manifolds, electrical engineering awards,
				cyberneticists, articles with example lisp code, computer libraries, javaScript libraries,
				graphics libraries, python libraries, python software, cryptographic software,
				voIP software, open formats, computer programming tools, database professionals,
				computer aided software engineering tools, software engineering disasters,
				mathematical tools, equations, combinatorics on words, office open XML,
				free communication software, free multimedia codecs\, containers\, and splitters,
				linux magazines, screensaver, grammatical moods, java platform software,
				diagramming software, technical communication tools, file sharing programs,
				communication software, web software, desktop publishing, virtual reality pioneers,
				bouncer (doorman), blog software, google earth, sudoku, QWERTY mobile phones,
				keyboard layouts, KDE platform, time signal radio stations, c++ standard library,
				gates, charles lindbergh, proprietary database management systems,
				electric power transmission system operators, connection machine,
				IBM mainframe computer operating systems, touchscreen mobile phones, computer keys,
				electric fish, mailing list, researchers in geometric algorithms, list of google doodles,
				COBOL, battery shapes, visi on, electrical signal connectors, audiovisual connectors,
				perl writers, rangekeeper, military computers, notetaking software, environmental design,
				electrical engineering books, numerical software, URI scheme, telephony equipment,
				software engineering publications, c libraries, leet, brain computer interfacing in fiction,
				robotics lists, c preprocessor, track via missile, view through rate, signoff (electronic design automation),
				radio paging, creative commons licensed works, list of e mail scams, diff,
				disney attractions that have used audio animatronics, internet based works,
				telephone card, magic lantern, wi fi, 3 d films, linux based devices,
				books available as e books, x ray astronomy, operating system distributions bootable from read only media,
				occupational safety and health, mathematical constants, photovoltaics manufacturers,
				unix process and task management related software, transcription, internet meme,
				free educational software, transliteration, electric power transmission systems in the united states,
				statistics books, statistics related lists, linux books, robotics books, books on perl,
				20Q, computer law, arithmetic, elementary mathematics, binary operations, AM expanded band,
				virtual learning environments, free screen readers, data visualization software,
				dot com, machine tool builders, people associated with the finite element method,
				people associated with networking industry, people involved with unicode,
				cypherpunks, crypto anarchism, files, boot loaders, operating system criticisms,
				A/UX, PDF software, nuclear magnetic resonance software, GNU project, mono project,
				self hosting software, mathematical software, spreadsheet software, software systems,
				most difficult language to learn, mathematics related lists, emacs,
				free software programmed in lisp, lisp software companies, compiling tools,
				perl, call signs, compilers by programming language, video on demand series,
				computer peripherals, GIS companies, electrical equipment manufacturers,
				telescope manufacturers, headphones, loudspeakers, computer aided design software,
				john von neumann theory prize winners, keyboards (computing), tablet PC,
				display devices, cruise missiles, watermills, control characters, unicode blocks,
				security guard, web application frameworks, x86 64 operating systems,
				mathematics stubs, mathematician stubs, electronic design automation people,
				computer algebra systems, hotmail, weaveability, data privacy, brainfuck,
				year 2038 problem, internet celebrity, national internet registries,
				certificate authorities, gnutella, fark, hubble space telescope,
				members of the conexus mobile alliance, beOS, amigaOS, mobile software,
				audio programming languages, mathematical terminology, oberon programming language family,
				constants, data types, mobile telecommunications software, real numbers, mobile agent,
				medical subject headings, electric grid interconnections in north america,
				atTask, programming idioms, symmetry, wikimedia foundation,
				sound operator, commercial type foundries, independent type foundries, MSN qnA,
				data segment, abstract data types, computer networking conferences, mathematics conferences,
				artificial intelligence conferences, programming languages conferences,
				software engineering conferences, theoretical computer science conferences,
				distributed computing conferences, telecommunication conferences,
				logic conferences, electronic design automation conferences,
				international society of intelligent biological medicine, EVA conferences,
				stack search, GIS file formats, grade of service, forterra systems, local property,
				national security agency, computing terminology, statistical terminology,
				internet terminology, software engineering terminology, formal methods terminology,
				air pollution dispersion terminology, usability professionals\' association,
				maxima and minima, technical drawing, glossary of shapes with metaphorical names,
				data loss prevention software, computational chemistry software,
				machine tools, machine tool, educational math software, programming language comparisons,
				mathematical comparisons, selection algorithm, government services portals, fouling,
				association for the advancement of artificial intelligence, filesystem hierarchy standard,
				computational chemistry software, molecular modelling software, molecular dynamics software,
				iterated logarithm, binary relation, eclipse (software), free documentation generators,
				mechanical computers, one of a kind computers, mains power connectors,
				bioinformatics organizations, artificial intelligence publications, plastics industry,
				modal logic, calling party, stiff equation, atrial fibrillation, mathematical relations,
				knowledge representation software, fortran libraries, rules of inference,
				Constructivism, intuitionism, computer occupations, logical truth, libre,
				articles with alice and bob explanations, recursion, login, DIRKS, GPSS,
				NESL, page layout, MVCML, control flow, FCAPS, file hosting, IRobot, SCOOP,
				esri, microformats, DNP3, WIDE, clitic, SPMD, unix security related software,
				readiris, TTCN, MUMPS programming language family, braille, moL, porcelain,
				Tiscali, EDRN, lightning, CAMBIA, data unit, STREAMS, launcher applications,
				electronic design automation companies, VMDS, nikola tesla, free web analytics software,
				web server management software, web server software, determinacy, wikia, diatomic molecule,
				kinetic monte carlo surface growth method, linear equation, window managers,
				layout engines, power grid, hardware routers, books about discourse analysis,
				SQL keywords, x servers, typesetting software, desktop publishing software,
				command line software, reunions, cola (programming language),
				comparison of business process modeling notation tools, clinical study design,
				software engineering organizations, digital video recorders,  science educational video games,
				higher order functions, windows CE, mathematical logic organizations, intranet portal,
				GTK+, free digital typography software, logo programming language family,
				human edited search engines, ICL mainframe computers, font managers, wii menu,
				microsoft database software, proposed telecommunications infrastructure,
				distributed computing projects, mathematics as a language, EGovernment in europe,
				internet censorship, decision support software, shadow volume, mySpace, auction houses,
				horse auction houses, teletraffic, verizon communications, john o. merritt, OS/2,
				mac OS, radioactive waste, Adware, disk file systems, Radio controlled aircraft,
				robot wars competitors, cisco systems, signaling system no 7, template engines,
				robotics companies, bluetooth software, retail POS systems, doomsday argument,
				modeling and simulation, java applications, polymers, thought,
				philosophy of mind, transpersonal studies, contemporary classical music,
				media formats, psychoactive drugs, video games by language, 
				japanese language video games, bass (sound), headaches, area, 
				history of computer science, silicon valley, time formatting and storage bugs, 
				animated films by technique, online publishers, intelligence, perception,
				information, concepts, mental health, consciousness, sleep, personality,
				voice types, ophthalmologists, sexual and gender identity disorders, 
				drug related deaths, heroin, aspirin, opium, negotiation tabletop games, 
				oral communication, pitch (music), tobacco, smoking, alcohol abuse,
				film editors, gustation, otology, psychological fiction, 
				computer recycling, robots by country, myspace, deaths from neurological disease,
				transmitter sites by country, people with brain injuries, Midnight movie,
				history of neuroscience, epilepsy, robot hall of fame, psychologists,
				food safety, cognitive scientists, telecommunications buildings,
				Film editing, Music theorists, documentaries about psychology,
				film awards for best visual effects, best visual effects academy award winners,
				crossword, graphical sound, radar networks, online retail companies by country,
				online music stores, CGI characters, computer science education, Cholera,
				defunct online companies, neuroscientists, neuroscience organizations, 
				IEEE edison medal recipients, internet society, psychology organizations,
				Drug rehabilitation, Pain, CCNA networking academy program, mathematical tables,
				unsolved problems in neuroscience, UAVs and drones by country, meninges,
				tourette syndrome, computing lists, cognitive science literature,
				cel shaded animation, progress spacecraft, blackBerry software, 
				people with schizophrenia, windows mobile, neurologists, IEEE medal of honor recipients,
				tian yuan shu, mereology, tier 1 networks, windows XP, brain fitness video game,
				IBM tivoli unified process (ITUP), melody, harmony, music theory, novell vibe, 
				electronic documents, digital media organizations, information technology by country,
				supercomputing in china, Criminology, International standard, 
				institute of electrical and electronics engineers, google employees,
				biomorphic robots, attention deficit hyperactivity disorder, combinatorialists,
				Problem solving, Euclidean solid geometry, Biorepositories,
				Telecommunications lists, Transformation (function), Classical ciphers,
				Transducers, Sympathomimetics, Mechanisms, Internet by continent,
				Lithium ion batteries, Robotics in fiction, Robot video games,
				Online gaming services, Insurance, Lenses, Database companies, Spirals,
				Mnemonic, Webcomic, Pleasure, Television station, Entertainment robotics, 
				Mathematical economists, Robotics media, Privacy, Speech, Personal identification documents,
				Cocaine, Amazon.com, Carbon dioxide, Identity document, CHP plants by country,
				Smart grids by country, Mains electricity by country, DragonFly BSD, 
				Robotic submarines, Massively multiplayer online role playing game,
				Information technology audit, Spinal cord, Internet Protocol based network software,
				Electricity markets, Neurosurgeons, Typefaces, Online companies, Autonomy,

				Linguistic controversies, Sociolinguistics, Graphemes, inuit phonology,
				Lexicography, Vocabulary, Reading, Writing systems, Dialects, Linguistic typology,
				Language contact, Dialectology, Rhetoric, Linguistic morphology, Unsolved problems in linguistics,
				WikiProject Linguistics, Linguistic units, Word play, Historical linguistics, Philology,
				Linguistic research, Grammar, Syntacticians, Linguists, Spelling, Toponyms,
				Tone %28linguistics%29, Interlinguistics, Linguistics lists, Lexis, Psycholinguistics,
				Word games, History of linguistics, Beatboxing, Diacritics, Reduplicants,
				Language orthographies, Grammars of specific languages, Code-switching,
				English dialects, Microphonesm, Language comparison, Linguistics publications,
				Nahuatl dialects, Japanese phonology, Interjections, list of writing systems,
				verbs, digraphs, trigraphs, bertrand russell, orthographers, vowel shifts,
				eurolinguistics, homophonic translation, pragmatics, thematic relation,
				monolingualism, differences between american and british english (vocabulary),
				mondegreens, uralic languages, indo european languages, language phonologies,
				language interpretation, ideophone, logical syntax, numeration, grammatical number,
				onomatopoeia, grammatical modifier, dative case, collation, structuralism, resultative,
				collation, TEVL, syntactic relationships, pleonasm, english as a foreign or second language, 
				narrative forms, german speaking countries, english speaking countries and territories, 
				arabic speaking countries and territories, archaeological corpora,
				semitic words and phrases, japanese language, tamil language, chinese dialects,
				bantu languages, chinese language media, standard chinese, language classification, 
				sign language, Neologism, Logical symbols, Interpretation (philosophy), Dichotomy,
				Epithet,
				
				'
				# 'moL' => 'method of lines' could be kept. but no time
				# 'EDRN' => 'Early Detection Research Network', but it's bioinformatics
				;
	@excluded = split /(?<!\\),\s*/, $excluded;
	for(@excluded){
		s/\\,/,/g;
	}

	push @excluded, (1990 .. 2010);

	%whitelist = ('Telephony' => 'Voice over IP, Secure communication',
				 'Social network services' => 'Reputation management, Social bookmarking,
					 Instant messaging, YouTube, Facebook, Web of trust, Skype, Orkut, Social web,
					 Flickr, MySpace, Social computing, Tag cloud, Social network service, Twitter,
					 Tagspace, Microblogging, SocialRank, Social graph, Media sharing,
					 Computational trust, Foursquare (social networking), Semantic Social Network,
					 Collaborative network, Crowd computing, User-generated content, OpenSocial,
					 FriendFeed',
				 'web 2.0' => 'web syndication formats, web 2.0 neologisms, Social Desktop,
				 	open government, collaborative mapping, ',
				 'Auctioneering' => 'Auction theory, Auction, Request for proposal, Winner\'s curse,
				 Dutch auction, Vickrey auction, English auction, Reverse auction, Japanese auction,
				 Double auction, Proxy bid, First-price sealed-bid auction, Combinatorial auction,
				 Bidding, Mystery auction, French auction, Demsetz auction, Forward auction,
				 Buyer\'s premium',
				 'Virtual reality communities' => 'Second Life',
				 'Virtual communities' => 'Second Life, Wiki communities, EBay, Online deliberation,
				 Web community, Global village (term), Online participation,
				 Virtual scientific community',
				 'Light sources' => '',
				 'Etymology' => 'Toponyms',
				 'Translation' => 'Machine translation',
				 'Domain name system' => '',
				 'Macintosh platform' => '',
				 'telephone services' => '',
				 'film and video terminology' => '',
				 'Social constructionism' => '',
				 'Applied linguistics' => 'Computational linguistics',
				 'multilingualism' => '',
				 'Mobile computers' => '',
				 'Risk management' => '',
				 'Personal identification' => '',
				 'Computing output devices' => '',
				 'Virtual communities' => '',
				 'Servers' => '',
				 'Computing and society' => '',
				 'Air dispersion modeling' => 'Pollution, Plume (hydrodynamics), Atmospheric dispersion modeling,
				 Wind profile power law, Log wind profile, Flue gas stack, Line source,
				 Air pollution dispersion terminology, Air Quality Modeling Group, Low-carbon emission,
				 Puff model, Transport Chemical Aerosol Model,
				 ',
				 'Internet broadcasting' => '',
				 'Philosophers of language' => 'Noam Chomsky, Bertrand Russell',
				 'Phonetics' => 'Transcription',
				 'Semantics' => 'Formal semantics, General semantics, Semantic units,
				 Word sense disambiguation',
				 'Microcomputers' => '',
				 'Free content' => '',
				 'Wi-Fi' => '',
				 'Office software' => '',
				 'Game controllers' => '',
				 'Virtual economy' => '',
				 'Free text editors' => '',
				 'Encryption devices' => '',
				 'GPS' => 'Navigation',
				 'Digital photography' => '',
				 'Search engine optimization' => '',
				 'Pronouns' => '',
				 'Embedded operating systems' => '',
				 'Computer scientists' => 'Turing Award laureates',
				 'X Window System' => '',
				 'PowerPC operating systems' => '',
				 'Email' => '',
				 'Malware' => 'Bots',
				 'Free software culture and documents' => '',
				 'Free development toolkits and libraries' => '',
				 'Microsoft Windows' => '',
				 'Creative Commons' => '',
				 'Credit cards' => 'Credit card terminology',
				 'Minicomputers' => '',
				 'Computer file systems' => 'Disk file systems',
				 'Chess theory' => '',
				 'Broadband' => '',
				 'video on demand' => '',
				 'Wind power' => '',
				 'Electric railways' => 'Rapid transit',
				 'Rapid transit' => '',
				 'Tram transport' => '',
				 'Light rail' => '',
				 'Glass' => 'Glass physics, Glass engineering and science',
				 'Electric power infrastructure' => 'Electrical grid, Power stations',
				 'Solar power' => 'Solar powered vehicles',
				 'Firefighting' => 'Incident management',
				 'cameras' => 'Cameras by type',
				 'Cameras by type' => '',
				 'Glass architecture' => '',
				 'Renewable energy power stations' => '',
				 'Power stations' => 'Power station technology',
				 'Electric buses' => '',
				 'Electronic currencies' => '',
				 'Label printer' => '',
				 'Biofuels' => '',
				 'Internet culture' => '',
				 'Staining' => '',
				 'heating, ventilating, and air conditioning' => '',
				 'integers' => 'parity, large integers, integer sequences',
				 'electric vehicle manufacturers' => '',
				 'verbs by type' => '',
				 'humanoid robots' => '',
				 'entertainment robots' => '',
				 'computer animation' => '',
				 'XML' => '',
				 'electric vehicles' => '',
				 'UAVs and drones' => '',
				 'military robots' => '',
				 'rechargeable batteries' => '',
				 'glycosaminoglycans' => '',
				 'blogging' => '',
				 'data remanence' => '',
				 'bitTorrent' => '',
				 'chess engines' => '',
				 'emulation software' => '',
				 'ferromagnetic materials' => '',
				 'syntactic entities' => '',
				 'payment systems' => '',
				 'corrosion' => '',
				 'mobile web' => '',
				 'hypertext' => '',
				 'Content Management Systems' => '',
				 'web development software' => '',
				 'electric public transport' => 'electric rail transport',
				 'electric rail transport' => 'urban rail transit',
				 'application programming interfaces' => '',
				 'resins' => '',
				 'video blogging' => '',
				 'social media' => '',
				 'software project management' => '',
				 'software development philosophies' => 'Agile software development',
				 'parts of speech' => '',
				 'software development process' => '',
				 'usenet' => '',
				 'hacking (computer security)' => '',
				 'phonology' => '',
				 'operating system families' => '',
				 'networking hardware' => '',
				 'touchscreens' => '',
				 'online encyclopedias' => '',
				 'glass compositions' => '',
				 'mobile operating systems' => '',
				 'remote desktop services' => 'remote desktop services, desktop virtualization,
				 						virtual network computing',
				 'firmware' => 'BIOS',
				 'windows NT' => '',
				 'cloud applications' => '',
				 'typesetting programming languages' => '', # TeX excluded here
				 'fax' => '',
				 'VHS' => '',
				 'orthography' => '',
				 'content control software' => '',
				 'character sets' => '',
				 '4GL' => '',
				 'java specification requests' => '',
				 'java enterprise platform' => '',
				 'syntactic categories' => '',
				 'syntactic transformation' => '',
				 'robotics competitions' => '',
				 'Multi touch' => '',
				 'telephone exchanges' => '',
				 'Embedded Linux' => '',
				 'cyberwarfare' => '',
				 'satellite telephony' => '',
				 'simulation programming languages' => '',
				 'musicology' => '',
				 'animation terminology' => '',
				 'grammatical cases' => '',
				 'hebrew language' => '',
				 'semitic languages' => '',
				 'esperantists by country' => '',
				 'language families' => '',
				 'pyrotechnics' => '',
				 'special effects' => 'pyrotechnics, visual effects', 
				 'cognition' => '',
				 'branches of psychology' => '',
				 'sensory organs' => '',
				 'psychological schools' => '',
				 'drugs acting on the nervous system' => '',
				 'popular psychology' => '',
				 'Stroke' => '',
				 'computer science awards' => 'turing award laureates',
				 'brain tumor' => '',
				 'dementia' => '',
				 'bipolar disorder' => '',
				 'autism' => '',
				 'dyslexia' => '',
				 'optometry' => '',
				 'extrapyramidal and movement disorders' => '',
				 'motor neurone disease' => '',
				 'computer keyboards' => '',
				 'archaeological corpora documents' => '',
				 'memory disorders' => '',
				 'cognitive disorders' => '',
				 'cubes' => '',
				 'prosody' => '',
				 'video game graphics' => '',
				 'sigma agonists' => '',
				 'internationalization and localization' => '',
				 'animation techniques' => '',
				 'brain disorders' => '',
				 'neurological disorders' => '',
				 'central nervous system disorders' => '',
				 'mental and behavioural disorders' => '',
				 'Philosophy of language' => '',
				 'Minimal surfaces' => '',
				 'Neurotoxins' => '',
				 'Stereoscopy' => '',
				 'Unmanned aerial vehicles' => '',
				 'Unmanned vehicles' => '',
				 'Identity management' => '',
				 'Mental processes' => '',
				 'Sensory system' => '',
				 'Motor system' => '',
				 'Eye'	=> '',
				 'Hazard analysis' => '',
				 
				);

	$stopterm = 'see also, also see, data encryption software, data analysis software,
					data compression software, list of data recovery software,
					note 1, note 2, note 3, note 4, example 1, example 2, example 3,
					example 4, example (ext), example a, example b,
					theorem (ext), proof (ext), rule (ext), requirement,
					shock value, two face, health level 7, testament (comics),
					the linux link tech show, over extended, very extended, start page, 1 wire,
					list of mathematics categories, please note, without overcharge,
					a diversity, no threshold, make (magazine), go!explore, simplified,
					locations, constructs, exponentials, method of images, no solution,
					real number, self recognition, effectiveness, voyager 1, voyager 2,
					features of the opera web browser, an exceptionally simple theory of everything,
					g value, ants, ims, theorem, packed, a index, copyright, shorting, shorted,
					overlay (programming), turning, persons, interoperability, forcing, relative to,
					almost surely, definition, programming tool, trim (programming), analogy,
					archive it, list of software for molecular mechanics modeling, election,
					subset, liveD, completeness, leveraged, executable, equational, areas of mathematics,
					networks, copying, if and only if, sufficiently large, lemmas, tuning, angle,
					symbolics, conTeXt, case study, linear, ember (company), estimation,
					worse is better, a conversion, a equivalence, a weighting, a life,
					a group, a computable, a helix, a helixes, a helices, a cathode,
					a site, a law, a 0 system, a loop, a star, a station, a shell,
					a plus, a mean, a genus, a key, checKing, locating, rewriting,
					ranging, paging, detection, concept, sparse, interfaces, experiment,
					choice, decomposition, potentially, localization, probabilistic,
					transforms, proofs, comparative, conjecture, useful, usefulness, report,
					l(r), AD+, variables, combination, calculation, compensation, statistical, statistically,
					apply, infinity, triangles, inequalities, stochastic, dimensionally, dimensional,
					multidimensional, inteGrate, random, rolling, push down, topological, output,
					combinatorial, sorting, data general one, stereo, randomized, utilization,
					tracing, enumeration, variational, syntactic, plan, integer, image,
					portuguese blogs, LEd, coefficient, average, geometrical, sphere,
					analytics, smoothing, rectangle, algorithm, proActive, gas, gain,
					workaround, non interactive, v (operating system), argument, phrase,
					DISCover, discoverEd, entity, EXist, off target, limits, mathematical,
					atomic orbital, anti block system, k times differentiable, variance,
					cube, blend, discriminant, we localize, interview, usable, unusable,
					came, median, crowds, end (topology), for each, for position only,
					weight function, reply, randomly, i. j. good, virtual memory system,
					manaGeR, putting on, array, transversal, e science, atom (standard),
					equation, subsequence, image space, lead, substructure, servers,
					south korea, system, lag, infinite, liquid, expansion (model theory),
					well order, slope, precondition, CS1, divergence, desktop,  starch companies,
					dimensionality, covariance, sprang, digitizing, timeline, s system,
					numerics, electrical, permanent, axiom, cluttering, keY, instability,
					not identifiable, ECLiPSe, bubbles, visIt, identifier, adjacent,
					mean, systemics, statistic, subsetting, geometrically, COinS, tadarus,
					undirected, less, counter, web course tools, timer, cumulant, l (complexity),
					surround, astrological age, nontrivial, admittance, medial, essence,
					bypassing, baselining, PREview, operand, responsiveness, resultant,
					loading, grouping, expect, triangle, tinyLinux, syntactical, ECos,
					virtually, vagueness, query interface, chart, simple expression, wiring,
					adapter, reDoS, meme, knowledge 1, knowledge iN, negative result,
					lock key, positive result, the support, laws of form, reliability engineering,
					u.n.p.o.c., the cult of the amateur, out(fn), zero (linguistics), in focus,
					cotton, layout (computing), about entropy, state (controls), in game, on world,
					a new kind of science, best practice, OCR a font, static vs. dynamic,
					development (topology), two stage model of free will, almost disjoint,
					the international records management trust, impact (mechanics), restriction of,
					bounded above, bounded below, bounded from below, bounded from above,
					compatible with, almost complex, combined systems, % operator, talk it!,
					by chance, failing badly, grand challenge, list of coastal weather stations of the united kingdom,
					interpretation (model theory), guardium\, an IBM company, up regulation,
					down regulation, unified model, audio visual art, related rates, property (programming),
					institute for operations research and the management sciences, operator,
					the unreasonable effectiveness of mathematics in the natural sciences,
					processing (software), instrumentation, two phase method, gums, efficient (statistics),
					perspective (graphical), string theory, chemical file formats, advice (complexity),
					reduction (complexity), complete (complexity), complement (complexity),
					low (complexity), certificate (complexity), dynamic data driven application system,
					smart card application protocol data unit, free software programmed in objective c,
					microsoft windows security technology, interpretation (logic), 
					list of philosophy categories, memory, emotion, hunger, 
					media by format, surnames by theme, self, symbols, computing by natural language,
					date and time representation, size, haiku, 95%, 68%, 68.2%, 95.4%, 99.7%,
					information technology places, special effects, knuckle heads, 
					the compendious book on calculation by completion and balancing,
					axiom a, fellows of the society of experimental psychologists,
					fellows of the international society for computational biology,
					wikipedia books on psychology, wikipedia books on computer science,
					wikipedia books on mathematics, wikipedia books on linguistics,
					wikipedia books on internet, wikipedia books on relationships, 
					wikipedia articles incorporating text from the federal standard 1037C,
					utility, what computers can\'t do, empirical, 
					table 1: concept definition list (metadata modeling),
					list of color palettes, list of video game console palettes,
					list of 16 bit computer hardware palettes, list of 8 bit computer hardware palettes,
					list of software palettes, list of monochrome and RGB palettes, U3,
					Relative change and difference, Just in case, 
					
					'
				# FIXED: "list of mathematics categories" are many wrongly extracted inter-category relations
				# by dbpedia. There may lurk more similar mistaken relations :(
				# FIXED: "list of philosophy categories" is same wrong.
				# "areas of mathematics" is another wrong category. it's the subcategory of
				# "Statistics|Stochastic processes|Probability theory" !
				# ants => "ANts" & "ANTS", ims => "IMs",
				 ;
	%stopterm = map { s/\\,/,/g; lc($_) => 1 } ( split /,\s*/, $stopterm );

	$reliantLemmas = 'dimension, diagrams, simulation, noise, potential, feedback, sequence,
					  shape, matching, computation, synchronization, utility, detectors,
					  light, emergence, rotation, embedding, subroutine, data, iteration,
					  recursion, availability, code, computer, determine, speedup, ideals,
					  piecewise, frequency, bit, bottleneck, circles, lagrangian, biasing,
					  pairing, tuple, configurations, lookup, gapping, vectors, wave,
					  digital, lookahead, heat, protocols, persist, soundness, retargeting,
					  surface, curve, melting, integrals, map, peering, non, hyperlink,
					  imaging, algorithms, resource, polynomial, library, load, measure,
					  event, function, process, node, method, connection, visualization,
					  comparative, structured systems analysis and design method,
					  tracking, learning, visual, means, interaction, part, feature, 
					  pulse, environment, 
						';
	my @reliantLemmas = lemmatize( split /,\s*/, $reliantLemmas );
	%reliantLemmas = map { getLemma($_) => 1 } @reliantLemmas;
	my $reliantLemmaCount = @reliantLemmas;
	print $tee "$reliantLemmaCount lemmas are marked as reliant\n";

		# exclude all children of the key term, except terms in the value list
	my %whiteEdgeList = ( 'c programming language' => 'ANSI C',
						   'electric power blackouts' => 'power outage',
						   'secretary problem' => 'marriage problem, sultan\'s dowry problem, fussy suitor problem,
						   							the googol game, ',
						   	'request for comments' => 'IETF RFC',
						 );

	my ($parent, $childrenList, @children, $child);
	my ($parentCount, $whiteEdgeCount);
	while( ($parent, $childrenList) = each %whiteEdgeList){
		$parent = decap($parent);
		@children = split /,\s*/, $childrenList;
		for(@children){
			$child = decap($_);
			$whiteEdge{$parent}{$child} = 1;
			$whiteEdgeCount++;
		}
		$parentCount++;
	}
	print $tee "$parentCount parent terms excluded, except $whiteEdgeCount white edges\n";

						# parent					=> children
	my %blackEdgeList = ( 'Computational models' 	=> 'Computing',
						  'manifolds'				=> 'dimension',
						  'Unicode'					=> 'Optical character recognition',
						  'statistical charts and diagrams' => 'smoothing, outlier',
						  'bionics'					=> 'methods of manufacture',
						  'EMBnet'					=> 'collaboration network',
						  'ALGOL'					=> 'algorithmic language',
						  'Autopilot'				=> 'track control system',
						  'chatterbots'				=> 'artificial linguistic internet computer entity,
						  									virtual woman',
						  'SQL data access'			=> 'Middleware',
						  # deleted in newest wiki. don't bother to update it
						  'data mining'				=> 'neural networks',
						 );
	my $blackEdgeCount = 0;
	$parentCount = 0;
	while( ($parent, $childrenList) = each %blackEdgeList){
		$parent = decap($parent);
		@children = split /,\s*/, $childrenList;
		for(@children){
			$child = decap($_);
			$blackEdge{$parent}{$child} = 1;
			$blackEdgeCount++;
		}
		$parentCount++;
	}
	print $tee "$blackEdgeCount black edges of $parentCount parent terms excluded\n";

	$excludedX = 'Applied linguistics, maude system, mzima networks, flat file database, dependability,
					fiber (mathematics), inbound marketing, multiplicative group of integers modulo n,
					UPCRC illinois, sekChek classic, sekChek local, ceramic engineering, neutral zone,
					website parse template, experimental uncertainty analysis, tomcar, DDR SDRAM,
					lamport\'s distributed mutual exclusion algorithm, frege\'s propositional calculus,
					congruence lattice problem, linear subspace, elementary group theory, sortSite,
					tensilica instruction extension, algorithmic skeleton, forte 4GL, sensitivity analysis,
					mathematical economics, shot transition detection, queueing model, transputer,
					SSL explorer: community edition, osmius, MTS system architecture, AC power,
					disk compression, dirac bracket, top hat beam, electronic privacy information center,
					desktopX, java business integration, sampling bias, test automation framework,
					Hierarchical query, IVideosongs, algorithm, unixWare, Common Intermediate Language syntax,
					software engineering organizations, Mean value theorem, automatic terminal information service,
					SSL explorer: community edition, bottom up parsing, wirth syntax notation,
					packet loss concealment, Quadratic assignment problem, linear bottleneck assignment problem,
					assignment problem, typed lambda calculus, link (telecommunications), 3G MIMO,
					strophoid, abstract rewriting system, economic model, ISO/IEC 9126, fifth generation computer,
					social software in education, x ray image intensifier, strahler number, image search optimization,
					metric (mathematics), short (finance), exact cover, AKS primality test, open grid forum,
					learning object, sense (molecular biology), SpagoBI, long tail traffic, e mail privacy,
					computer supported collaboration, web mapping, log analysis, nexus (standard),
					CHARA array, superconductivity, cell lists, azeotrope (data), microcom networking protocol,
					openTherm, dbForge studio for mySQL, apptek, open source job scheduler, x ray image intensifier,
					object theory, logical conjunction, information retrieval, web server, topoFlight,
					information warfare monitor, blind experiment, DVB T, XSL formatting objects, SM4All,
					random compact set, renormalization group, KNX (standard), limit of a sequence,
					computable function, optimal design, reflective subcategory, battery (vacuum tube),
					wick\'s theorem, open firmware, apocope, ruBee, history of superconductivity,
					clearForest, onkosh, control flow, sensorML, multiprocessing, EEMBC, openFormula,
					MIKEY, gvSIG, JSystem, drive by wire, topoFlight, raknet, minitel, webDAV,
					internet relay chat, ERROL, parallax scanning, bioconductor, CICS, SMS,
					NTRUEncrypt, controlNet, XACML, caBIG, HARDI, treebank, memoization,
					appWare, interCall, readspeaker, pathema, productCenter, NESI, intraText,
					transformity, webPlus, BRENDA, eiffelStudio, garageBand, NForce, agentSheets,
					javaOne, TTEthernet, AMTrix, neuroinformatics, greedoid, ETICS, scriptella,
					realFlow, enStratus, coolfluid, roaming, intercom, gradient copolymers, gridCC,
					CANaerospace, radiolocation, tandberg, Polycarbonate, antConc, FJG, Lectora,
					modelica, VUE, AMBER, Mechanoreceptor, bioSim, electromigration, GOMS,
					CCSID, globalPlatform, geneWeb, FORscene, PerlScript, MSConfig, Openfiler,
					Multivibrator, funcDesigner, OpenOpt, BLISS, wikiMapia, METS, IBM webSphere commerce,
					software review, version space, computability theory, chief information officer,
					education and training of electrical and electronics engineers, Rank into rank,
					magnetic ink character recognition, sparse matrix, ASC X9, NX bit, delta functor,
					requirement prioritization, program optimization, exterior angle theorem,
					serialization, radiant barrier, image (mathematics), pinball 2000, frama c,
					mrs. miniver\'s problem, radio over fiber, accelerated language learning,
					f. r. carrick institute, Learning platform, logogen model, edgewood chemical biological center,
					Loudspeaker, previous bose headphones, analysis of subjective logics,
					scannerless parsing, software verification, n2rrd, BLAST, unix security,
					holistic data management, regressive discrete fourier series, 
					address verification system, norman mcLaren, burroughs large systems instruction sets,
					v statistic, Cognition, english in computing, study software, 
					metadata modeling, abstract machine, Turing\'s proof, 
					Globally Harmonized System of Classification and Labelling of Chemicals,
					';
	@excludedX = split /,\s*/, $excludedX;
}

# sample parameters:
#						taxonomyFile => "c:/wikipedia/csmathling-full.txt",
#						rootterms => \@treeRoots,
#						ancestorsLoadFile => $ANCESTORS_LOAD_FILENAME,
#					   	ancestorsSaveFile => $ANCESTORS_SAVE_FILENAME,
#					   	debugFlag => $DEBUG, newTermMode => ConceptNet::NEWTERM_COMPLEX
sub initialize
{
	my %args = @_;

	my $taxonomyFile = $args{taxonomyFile};
	die "Ontology file is not given!\n" if !$taxonomyFile;
	die "Ontology file '$taxonomyFile' doesn't exist!\n" if !-e $taxonomyFile;

	if($args{newTermMode}){
		setNewTermMode($args{newTermMode});
	}
	if(exists $args{useIC}){
		$CALC_SIMI_USE_IC = $args{useIC};
	}

	iniLists();

	my $rootterms = $args{rootterms};
	my $ANCESTORS_LOAD_FILENAME = $args{ancestorsLoadFile};
	my $ANCESTORS_SAVE_FILENAME = $args{ancestorsSaveFile};

	my $TAXONOMY;

	print $tee "Loading edges from '$taxonomyFile':\n";

	open_or_die($TAXONOMY, "< $taxonomyFile");

	my $conceptNetSize = \$sizeof{\@conceptNet};

	my $progresser = makeProgresser( vars => [ \$., $conceptNetSize ] );

	my $i;
	my ($term, $cat1, $depth);
	my $line;

	my $maxLoadEdgeCount = $args{M} || 1000000;

	while($line = <$TAXONOMY>){
		&$progresser();

		next if $line =~ /^#/;

		last if $. > $maxLoadEdgeCount;

		trim($line);
		next if !$line;

		($term, $cat1, $depth) = split /\t/, $line;

		addEdge(\@conceptNet, $term, $cat1, 0);
	}

	print $tee "$. lines read from '$taxonomyFile'\n";
	print $tee "$$conceptNetSize edges, $termGID nodes\n";

	close($TAXONOMY);

	exclude(@excluded);
	excludeX(@excludedX);
	exclude4whitelist(\%whitelist);

	my $doAncestorExpansion = $args{doAncestorExpansion};

	if($args{useFreqPassupAttenuation}){
		$USE_FREQ_PASSUP_ATTENUATION = $args{useFreqPassupAttenuation};
	}

	if(! $ANCESTORS_LOAD_FILENAME){
		if($doAncestorExpansion){
			print $tee "Ancestor expansion will be made\n";
		}

		enumAncestors(\@conceptNet, $rootterms, \@ancestorTree, \@inheritCount, \@depthByBatch,
						\@attenuateByBatch, \@recAttenuateByBatch, $doAncestorExpansion);
	}
	else{
		loadAncestors(\@conceptNet, $rootterms, \@ancestorTree, \@inheritCount, $ANCESTORS_LOAD_FILENAME);
	}

	if($ANCESTORS_SAVE_FILENAME){
		saveAncestors(\@ancestorTree, $ANCESTORS_SAVE_FILENAME);
	}

}

sub NO_OP
{}

sub entropy
{
	my $sum = 0;

	for(@_){
		next if $_ <= 0;
		$sum += $_ * log($_);
	}
	return -$sum / log(2);
}

sub calcTokenEntropy($$$;$$)
{
									# $pCheckCount, $pMaxCheckCount are for profiling. they must be provided together
	my ($ancestorTree, $bfsDepth, $token, $pCheckCount, $pMaxCheckCount) = @_;
	
#	if($id <= 0 || $id >= $lemmaGID){
#		if($DEBUG & DBG_CALC_TOKEN_ENTROPY){
#			print $tee "Wrong lemma ID: $id\n";
#		}
#		return -1;
#	}
#	
#	my $lemma = $lemmaCache[$id]->[0];
	
	# don't calc the entropy of stop words. 
	# only for those short terms the stop words in them are kept. so the posting lists of these stop words
	# are short, and their entropies are small, which don't reflect their actual information
	if($stopwords{$token}){
		return 0;
	}
		
	my $postingList = $invTable{ $token };
	
	my $N = 0;
	my @postings;
	
	if($postingList){
		@postings = grep { $visited[$_ ] } @$postingList;
		$N = @postings;
	}

	if($N == 0){
		if($DEBUG & DBG_CALC_TOKEN_ENTROPY){
			print $tee "Token '$token' has empty posting list\n";
		}
		return 0;
	}
	
	# the shallower terms tend to be more general and more likely to subsume deeper terms
	@postings = sort { $bfsDepth->[$b] <=> $bfsDepth->[$a] } @postings;
	my ($i, $j);
	my ($tid1, $tid2);
	my @subsumed;
	my $checkCount = 0;
	
	# the order of the checks is not important. if we find that A subsumes B, and we don't know that
	# B subsumes C (since B is already subsumed, B is not checked), then
	# A must be an ancestor of C. so C won't be left out un-subsumed.
	for($i = 0; $i < $N; $i++){
		next if defined($subsumed[$i]);
		$tid1 = $postings[$i];
		
		for($j = $i + 1; $j < $N; $j++){
			next if defined($subsumed[$j]);
			
			$tid2 = $postings[$j];
			$checkCount++;
			
			if($ancestorTree->[$tid2]->{$tid1}){
				$subsumed[$j] = $i;
				next;
			}
			elsif($ancestorTree->[$tid1]->{$tid2}){
				$subsumed[$i] = $j;
				last;
			}
		}
	}
	
	if($pCheckCount && $N >= 10){
		$$pCheckCount += $checkCount;
		$$pMaxCheckCount += ( $N * ($N - 1) ) / 2;
	}
		
	my @topTermFreqs;
	my $termID;
	for($i = 0; $i < @postings; $i++){
		if(! defined($subsumed[$i]) ){
			$termID = $postings[$i];
			if( $freqs[$termID] ){
				push @topTermFreqs, $freqs[$termID] / $MC;
			}
		}
	}
	
	return ( entropy(@topTermFreqs), $N, scalar @topTermFreqs );
}

sub calcUnigramEntropies(;$)
{
	my $entropyFilename = shift;
	if($entropyFilename){
		$entropyFilename = getAvailName($entropyFilename);
	}
		
	my $unigram;
	
	my ($totalCheckCount, $totalMaxCheckCount, $efficiency) = (0, 0, 0);
	my $gramCount = 0;
	my $progresser = makeProgresser( vars => [ \$gramCount, \$totalCheckCount, \$totalMaxCheckCount, \$efficiency ],
										step => 1000 );

	my $M = keys %gUnigrams;
	print $tee "Calculating entropies of $M unigrams...\n";									

	%gramEnt = ();

	my ($entropy, $postingListLen, $topTermCount);
	my %gramPostingListLen;
	
	for $unigram(keys %gUnigrams){
		($entropy, $postingListLen, $topTermCount) = calcTokenEntropy(\@ancestorTree, \@bfsDepth, $unigram, 
								\$totalCheckCount, \$totalMaxCheckCount);
								
		$gramEnt{$unigram} = $entropy;
		$gramPostingListLen{$unigram} = [ $postingListLen || 0, $topTermCount || 0 ];
		
		$gramCount++;
		
		if($totalMaxCheckCount > 0){
			$efficiency = trunc(2, $totalCheckCount * 100 / $totalMaxCheckCount);
		}
		
		&$progresser();
	}
	
	print $tee "\nDone.\n";
	
	if(! $entropyFilename){
		return $M;
	}
	
	print $tee "Saving entropies to '$entropyFilename'...\n";
	
	my $ENT;
	if(! open_or_warn( $ENT, "> $entropyFilename" ) ){
		return 0;
	}
	
	my @unigrams = sort { $gramEnt{$b} <=> $gramEnt{$a}
									    ||
				 $gUnigrams{$b}->tfiaf <=> $gUnigrams{$a}->tfiaf
				 		} keys %gUnigrams;
	
	print $ENT "Unigram,Entropy,Frequency,TFIAF,Posting List Len,Top Term Count\n";
	
	for $unigram(@unigrams){
		print $ENT join( ",", $unigram, $gramEnt{$unigram}, $gUnigrams{$unigram}->freq, 
								$gUnigrams{$unigram}->tfiaf, @{ $gramPostingListLen{$unigram} }
						), "\n";
	}
	print $tee "Done.\n";
	
	return $M;
}

sub expNormalizeArray($$$)
{
	my ($expCoeff, $array, $outArray) = @_;

	my $sum = sum(@$array);

	if(!defined($sum) || $sum == 0){
		@$outArray = ();
		return 0;
	}

	my $expsum = 0;

	my @expArray;

	my $matchCutoff = 0;

	my @sortedScores = sort { $b <=> $a } @$array;
	if(@$array > $KEEP_MATCH_TOP_N_RESULTS){
		$matchCutoff = max( $sortedScores[$KEEP_MATCH_TOP_N_RESULTS],
								$CUTOFF_OF_BEST_MATCH * $sortedScores[0] );
	}
	else{
		$matchCutoff = $CUTOFF_OF_BEST_MATCH * $sortedScores[0];
	}

	$sum = 0;

	my $cutoffCount = 0;

	for(@$array){
		if($_ < $matchCutoff){
			push @expArray, 0;
			$cutoffCount++;
		}
		else{
			push @expArray, exp($expCoeff * $_) - 1;
			$sum += $_;
		}
		$expsum += $expArray[-1];
	}

	if($DEBUG & DBG_MATCH_TITLE){
		print $LOG "match cutoff at: $matchCutoff, $cutoffCount are cut off\n";
		print $LOG "expsum: $expsum\n";
	}

	# if $sum > 1, do normal exp normalization.
	# otherwise, make the final sum total to be $sum
	if($sum > 1){
		$sum = 1;
	}

	my @expNormalizedArray = map { trunc(4, $_ / $expsum) } @expArray;

	@$outArray = @expNormalizedArray;

	# the sum of @expNormalizedArray is always 1
	# so we need to use the returned $sum to do further scaling
	return $sum;
}

sub normalizeArray
{
	my $array = shift;
	my $sum = sum(@$array);

	if($sum == 0){
		return ();
	}

	# array elements are all too small. keep them intact
	if($sum < 1){
		return @$array;
	}

	return map { $_ / $sum } @$array;
}

# index by lemma (rather than by lemma id). so words with different suffices can still match (with a discount)
sub buildIndex($$$$)
{
	my ( $term, $id, $lemmaIDs, $contextLemmaIDs ) = @_;

=pod
	my (@lemmaIDs, @contextLemmaIDs, @stopwordGaps);
	my $sameLemmas = 0;

	# if $parentID is provided
	if( $parentID && $parentID > 0 ){
		my @parentLemmaIDs = @{ $termTokens[$parentID] };
		if( @parentLemmaIDs == @$lemmaIDs ){
			my $i;
			for($i = 0; $i < @$lemmaIDs; $i++){
				if($lemmaIDs->[$i] != $parentLemmaIDs[$i]){
					last;
				}
			}
			# if $parent and $term has the same lemma sequence, we don't index $term
			if($i == @$lemmaIDs){
				if($DEBUG & DBG_BUILD_INDEX){
					print $LOG "$.: Skip indexing $id '$term': same lemmas as $parentID '$terms[$parentID]'\n";
				}
				$sameLemmas = 1;
			}
		}
	}
=cut
		
	my $lemmaID;

	$termMainTokens[$id] = $lemmaIDs;
	# if no context, context start is the index of the end of the term
	$termContextStart[$id] = @$lemmaIDs;
	
	my @lemmaIDs = ( @$lemmaIDs, @$contextLemmaIDs );

	my $lemma;
	my %addedLemma;
	
	for $lemmaID(@lemmaIDs){
		$lemma = $lemmaCache[$lemmaID]->[0];
		next if $addedLemma{ $lemma };
		
		if(! exists $invTable{ $lemma }){
			$invTable{ $lemma } = [ $id ];
		}
		else{
			push @{$invTable{ $lemma }}, $id;
		}
		$addedLemma{ $lemma } = 1;
	}
	
	$termTokens[$id] = [ @lemmaIDs ];
}

sub getTermID($;$)
{
	my ( $term, $autoVivify ) = @_;

	return -1 if !$term;

	my $context;
	my $main;
	# treat the first "(" from the second letter as the beginning of the context
	my $contextStart = index $term, "(", 1;

	my ( @lemmaIDs, @contextLemmaIDs );

	# stopwords are kept. maybe they are useful to differentiate a term from another
	if( $contextStart >= 0 ){
		$context = substr($term, $contextStart);
		$main = substr($term, 0, $contextStart);
		@lemmaIDs = lemmatizePhrase($main);
	}
	else{
		$context = "";
		@lemmaIDs = lemmatizePhrase($term);
	}

	if( length($context) ){
		@contextLemmaIDs = lemmatizePhrase($context);
	}

	my $lemmaForm = join(" ", @lemmaIDs);
	if(@contextLemmaIDs > 0){
	 	$lemmaForm .= ',' . join(" ", @contextLemmaIDs);
	}
	
	my $id = $termLemmaTable{$lemmaForm};
	if( !defined($id) ){
		if(! $autoVivify){
			return -1;
		}
		else{
			push @terms, $term;
			push @conceptNet, [];
			push @edgeTable, {};

			$termLemmaTable{$lemmaForm} = $termGID;
			$id = $termGID;

			if($newTermMode == NEWTERM_COMPLEX){
				@lemmaIDs = grep { $lemmaCache[$_]->[1] != STOPWORD } @lemmaIDs;
				@contextLemmaIDs = grep { $lemmaCache[$_]->[1] != STOPWORD } @contextLemmaIDs;
				buildIndex( $term, $termGID, \@lemmaIDs, \@contextLemmaIDs );
			}

			$termGID++;
		}
	}

	return $id;
}

sub getTermIC
{
	my $id = getTermID($_[0]);
	if($id < 0){
		return 0;
	}
	return $ICs[$id];
}

# $childTerm, $parentID, $childID, capcount($childTerm)
sub updateEdgeTableNC($$$$)
{
	my $childTerm = lc(shift);
	my $parentID = shift;
											# $childID, capcount($childTerm)
	$edgeTableNC[$parentID]->{$childTerm} = [ @_ ];
}

sub doesEdgeExistNoCase
{
	my $childTerm  = lc($_[0]);
	my $parentID   = $_[1];

	if($parentID == -1){
		return (-1, -1);
	}
	if(exists $edgeTableNC[$parentID]->{$childTerm}){
		return @{$edgeTableNC[$parentID]->{$childTerm}};
	}
	else{
		return (-1, -1);
	}
}

sub isExcluded
{
	my ($node, $parent) = @_;
	if(!$parent){
		return $excluded{_}{$node};
	}
	return $excluded{$parent}{$node} || $excluded{_}{$node};
}

sub isExcludedX
{
	my $node = shift;
	$node = decap($node);
	return $excludedX{$node};
}

sub doesEdgeExistByID
{
	my ($childID, $parentID) = @_;

	return exists $edgeTable[$parentID]->{$childID}
}

sub doesEdgeExist
{
	my $childID  = getTermID($_[0]);
	my $parentID = getTermID($_[1]);

	if($parentID == -1 || $childID == -1){
		return 0;
	}
	return doesEdgeExistByID($childID, $parentID);
}

sub isStopTerm
{
	return $stopterm{lc($_[0])};
}

sub isBlackEdge
{
	my ($child, $parent) = decap(@_);
	return $whiteEdge{$parent} && !$whiteEdge{$parent}{$child} || $blackEdge{$parent}{$child} ;
}

sub hasIllegalChar
{
	for(@_){
		if(/  |[<>{}]/){
			return 1;
		}
	}
	return 0;
}

sub addEdgeByID($$$;$$)
{
	my ($pNet, $childID, $parentID, $childTerm, $parentTerm) = @_;

	if($parentID >= 0 && $childID >= 0){
		# parent and child has only slight difference. such as "kernel method" <- "kernel methods"
		if( $parentID == $childID ){
			if($DEBUG & DBG_ADD_EDGE){
				print $LOG "c '$childTerm' ~~ p '$parentTerm', addEdgeByID skipped\n";
			}
			return 0;
		}
		if(doesEdgeExistByID($childID, $parentID)){
			return 0;
		}
		push @{$pNet->[$parentID]}, $childID;
		$edgeTable[$parentID]->{$childID} = 1;
		$sizeof{$pNet}++;
		return 1;
	}
	return 0;
}

sub addEdge($$$;$)
{
	my ($pNet, $childTerm, $parentTerm, $isExtended) = @_;

	if( isStopTerm($childTerm) || isBlackEdge($childTerm, $parentTerm) ){
		return 0;
	}

	# little info contained in this term, ignore
	if($parentTerm =~ tr/[A-Za-z0-9]// <= 1 || $childTerm =~ tr/[A-Za-z0-9]// <= 1){
		return 0;
	}

	if( lc($childTerm) eq lc($parentTerm) ){
		if($DEBUG & DBG_ADD_EDGE){
			print $LOG "c '$childTerm' == p '$parentTerm', addEdge skipped\n";
		}
		return 0;
	}

	if( $isExtended ){
		my @childLemmas = lemmatizePhrase($childTerm);
		my @parentLemmas = lemmatizePhrase($parentTerm);
		if( @childLemmas == @parentLemmas ){
			my $i;
			for($i = 0; $i < @childLemmas; $i++){
				last if $childLemmas[$i] != $parentLemmas[$i];
			}
			# child & parent are identical (after lemmatization). discard this child
			if($i == @childLemmas){
				if($DEBUG & DBG_ADD_EDGE){
					print $LOG "c '$childTerm' ~~ p '$parentTerm', addEdge skipped\n";
				}
				return 0;				
			}
		}
	}
	
	my $parentID = getTermID($parentTerm, 1);

	my ($oldChildID, $oldCapCount) = doesEdgeExistNoCase($childTerm, $parentID);
	if( $oldChildID > 0 ){
		my $capCount = capcount( decap($childTerm) );
		if( $capCount > $oldCapCount 
			# the case that only the first letter is capital is ignored.
			# such as 
			# "stroke	episodic and paroxysmal disorders"
			# &
			# "Stroke	episodic and paroxysmal disorders"
		  ){
			if($DEBUG & DBG_ADD_EDGE){
				print $LOG "replace '$terms[$oldChildID]' => '$childTerm'\n";
			}
			#$termTable{$childTerm} 	= $oldChildID;
			$terms[$oldChildID] 	= $childTerm;

			updateEdgeTableNC($childTerm, $parentID, $oldChildID, $capCount);
		}
		else{
			if($DEBUG & DBG_ADD_EDGE){
				print $LOG "c '$childTerm' covered by '$terms[$oldChildID]' (p '$parentTerm'), ignored\n";
			}
		}
		return 0;
	}
	else{
		my $childID;

		if($isExtended){
			# if child term is an extended term, replace the tag with the parent term
			# so that the child will become unique, and the matched weight calculation will be more accurate
			$childID  = getTermID( "$childTerm ($parentTerm)", 1 );
		}
		else{
			$childID  = getTermID( $childTerm, 1 );
			# edge "lc($childTerm) <- $parentID" doesn't exist in edgeTableNC
			updateEdgeTableNC($childTerm, $parentID, $childID, capcount($childTerm));
		}

		return addEdgeByID( $pNet, $childID, $parentID, $childTerm, $parentTerm );
	}
}

our $sn;

sub push2(\@@)
{
	my ($array, @pushee) = @_;

	if($DEBUG & DBG_TRAVERSE_NET_LOW_OP){
		if(@pushee > 0){
			if(@pushee > 1 || $pushee[0] >= 0){
				print $LOG "$sn: push ", quoteArray(map { $terms[$_] } @pushee), "\n";
			}
			else{
				print $LOG "$sn: push ", join(",", @pushee), "\n";
			}
		}
	}

	return push @$array, @pushee;
}

sub pop2(\@)
{
	my $array = shift @_;
	my $popee = pop @$array;

	if($DEBUG & DBG_TRAVERSE_NET_LOW_OP){
		if($popee >= 0){
			print $LOG "$sn: pop '$terms[$popee]'\n";
		}
		else{
			print $LOG "$sn: pop $popee\n";
		}
	}

	return $popee;
}

sub shift2(\@)
{
	my $array = shift @_;
	my $shiftee = shift @$array;

	if($DEBUG & DBG_TRAVERSE_NET_LOW_OP){
		if($shiftee >= 0){
			print $LOG "$sn: deque '$terms[$shiftee]'\n";
		}
		else{
			print $LOG "$sn: deque $shiftee\n";
		}
	}

	return $shiftee;
}

sub unshift2(\@@)
{
	my ($array, @prependee) = @_;

	if($DEBUG & DBG_TRAVERSE_NET_LOW_OP){
		if(@prependee > 0){
			if(@prependee > 1 || $prependee[0] >= 0){
				print $LOG "$sn: prepend ", quoteArray(map { $terms[$_] } @prependee), "\n";
			}
			else{
				print $LOG "$sn: prepend ", join(",", @prependee), "\n";
			}
		}
	}

	return unshift @$array, @prependee;
}

sub dfsPostorder
{
	my %args = @_;

	my $D = $args{depth};
	my $callback = $args{callback} || \&NO_OP;
	my $tree = $args{tree} || \@conceptNet;
	my $roots = $args{roots};
	my $visited = $args{visited} || \@visited;
	my $dfsTree = $args{travTree} || \@dfsTree;
	my $dfsDepth = $args{dfsDepth};

	my @stack = @$roots;

	my @stackedParents = (0) x $termGID;
	$stackedParents[0] = 1;
	my @partialPath = (0);

	our ($parent, $node, @children);

	@$visited = (0) x $termGID;
	my @isDumped  = (0) x $termGID;
	@$dfsTree = map { [] } 1 .. $termGID;

	if($dfsDepth){
		@$dfsDepth = (0) x $termGID;
	}

	my $edgecount = 0;

	$isCyclic = 0;

	our $depth = 1;
	$parent = 0;


	while(@stack){
		$node = pop2 @stack;
		$visited->[ abs($node) ] = 1;

		if($node < 0){
			$parent = pop2 @stack;
			$depth--;
			$node = -$node;
			if($isDumped[$node]){
				die "Shouldn't happen: $node:$terms[$node] <- $parent:$terms[$parent]";
			}
			$isDumped[$node] = 1;

			&$callback($node, $parent, $depth);
			if($dfsDepth){
				$dfsDepth->[$node] = $depth;
			}

#			print $DUMP "$terms[$node]\t$terms[$parent]\t$depth\n";
			push @{$dfsTree->[$parent]}, $node;

			# At this point, all children of this node have been visited.
			# Backtrack, or remove this node from the partial path.
			$stackedParents[$node] = 0;
			pop @partialPath;

			progress(++$edgecount);

			next;
		}
		else{
			push2 @stack, $parent, -$node;

			@children = dedup( @{$tree->[$node]} );

			if(!isExcluded($node, $parent) && $depth <= $D){

				# add this node to the partial path
				$stackedParents[$node] = 1;
				push @partialPath, $node;

				for(@children){
					if($stackedParents[$_]){
						$isCyclic = 1;

						if($DEBUG & DBG_TRAVERSE_NET){
							push @partialPath, $_;
							print $LOG "CYCLE:\n";
							print $LOG join(", ", map { $terms[$_] } @partialPath), "\n";

							pop @partialPath;
						}
					}
				}

				push2 @stack, grep { !$visited->[$_] } @children;
				map { $visited->[ $_ ] = 1 } @children;
			}
			elsif(isExcluded($node, $parent)){
				if($DEBUG & DBG_TRAVERSE_NET){
					print $LOG "Node $node ($terms[$node]) excluded, children not visited\n";
				}
			}

			$depth++;
			$parent = $node;
		}
	}

	progress_end("$edgecount edges traversed");
}

sub dfsPreorder
{
	my %args = @_;

	my $D = $args{depth};
	my $callback = $args{callback} || \&NO_OP;
	my $tree = $args{tree} || \@conceptNet;
	my $roots = $args{roots};
	my $visited = $args{visited} || \@visited;
	my $dfsTree = $args{travTree} || \@dfsTree;
	my $dfsDepth	= $args{dfsDepth};

	my @stack = @$roots;

	my @stackedParents = (0) x $termGID;
	$stackedParents[0] = 1;
	my @partialPath = (0);

	our ($parent, $node, @children);

	@$visited = (0) x $termGID;
	@$dfsTree = map { [] } 1 .. $termGID;

	if($dfsDepth){
		@$dfsDepth = (0) x $termGID;
	}

	my $edgecount = 0;

	$isCyclic = 0;

	our $depth = 1;
	$parent = 0;


	while(@stack){
		$node = pop2 @stack;
		if($node < 0){
			$depth = -$node;
			while(@partialPath > $depth){
				$node = pop @partialPath;
				$stackedParents[ $node ] = 0;
			}
			next;
		}

		$visited->[ $node ] = 1;

		$parent = $partialPath[-1];

		&$callback($node, $parent, $depth);
		if($dfsDepth){
			$dfsDepth->[$node] = $depth;
		}

		progress(++$edgecount);

		push @{$dfsTree->[$parent]}, $node;

		@children = dedup( @{$tree->[$node]} );

		if(!isExcluded($node, $parent) && $depth <= $D){
			# add this node to the partial path
			$stackedParents[$node] = 1;
			push @partialPath, $node;

			for(@children){
				if($stackedParents[$_]){
					$isCyclic = 1;

					if($DEBUG & DBG_TRAVERSE_NET){
						push @partialPath, $_;
						print $LOG "CYCLE:\n";
						print $LOG join(", ", map { $terms[$_] } @partialPath), "\n";

						pop @partialPath;
					}
				}
			}

			push2 @stack, -$depth;
			push2 @stack, grep { !$visited->[$_] } @children;
			map { $visited->[ $_ ] = 1 } @children;
			$depth++;
		}
		elsif(isExcluded($node, $parent)){
			if($DEBUG & DBG_TRAVERSE_NET){
				print $LOG "Node $node ($terms[$node]) excluded, children not visited\n";
			}
		}
	}

	progress_end("$edgecount edges traversed");
}

sub dfsExpandAncestors
{
	my %args = @_;

	my $tree 				= $args{tree} 			|| \@conceptNet;
	my $roots 				= $args{roots};
	my $dfsTree 			= $args{travTree} 		|| \@dfsTree;
	my $bfsHashTree			= $args{bfsHashTree}	|| \@bfsHashTree;
	my $bfsDepth			= $args{bfsDepth};
	my $ancestorTree 		= $args{ancestorTree};
	my $ancestorInheritor 	= $args{ancestorInheritor};

	# make the first element in the $roots the top element in the stack
	# so it's the highest priority
	my @stack = reverse @$roots;

	my @dfsHashTree;

	my @stackedParents = (0) x $termGID;
	$stackedParents[0] = 1;
	my @partialPath = (0);

	our ($parent, $node, @children);

	my %visitCount = ( 0 => 1 );

	@$dfsTree = map { [] } 1 .. $termGID;

	our $depth = 1;
	$parent = 0;

	print $tee "DFS traverse to expand ancestors without adding cycles:\n";

	my ($nodecount, $edgecount, $newEdgeCount) = ( 0, 0, 0 );

	my $progresser = makeProgresser( vars => [ \$edgecount, \$nodecount, \$newEdgeCount ]);

	$sn = 0;
	while(@stack){
		$sn++;

		$node = pop2 @stack;
		if($node < 0){
			$depth = -$node;
			while(@partialPath > $depth){
				$node = pop2 @partialPath;
				$stackedParents[ $node ] = 0;
			}
			next;
		}

		$parent = $partialPath[-1];

		if(! $dfsHashTree[$parent]->{$node}){
			push @{$dfsTree->[$parent]}, $node;
			$dfsHashTree[$parent]->{$node} = 1;

			if(! $bfsHashTree[$parent]->{$node}){
				$newEdgeCount++;

				if(! defined($bfsDepth->[$node])){
					$bfsDepth->[$node] = $depth;
					if($DEBUG & DBG_TRAVERSE_NET){
						print $LOG "$sn: assign depth $depth to $node '$terms[$node]'\n";
					}
				}

				if($DEBUG & DBG_TRAVERSE_NET){
					print $LOG "$sn: new edge $parent '$terms[$parent]' (d: $bfsDepth->[$parent]) ",
								"-> $node '$terms[$node]' (d: $bfsDepth->[$node])\n";
				}
			}
		}

		my $inheritStatus = &$ancestorInheritor($node, $parent, $depth);

		# if a cycle is detected, the children of $node will not be expanded
		# i.e., the edge between $node <- $parent is simple discarded
		# but actually it never happened, is it because DFS avoids ALL the cycles?
		if($inheritStatus == -1){
			if($DEBUG & DBG_TRAVERSE_NET){
				print $LOG "$sn: CYCLE $node '$terms[$node]' & $parent '$terms[$parent]'\n";
			}
			next;
		}
		# the ancestor list of $node doesn't change.
		# if $node had been dfs-visited before, we don't need to propogate new ancestors
		# to its descendents
		elsif($inheritStatus == 0 && $visitCount{$node}){
			next;
		}

		$visitCount{$node}++;

		if(!isExcluded($node, $parent)){
			my $ancestorList = $ancestorTree->[$node];

			@children = grep { 			! $stopped[$_]
												&&
										! $stackedParents[$_]
												&&
										! $ancestorList->{$_}
												&&
									 ( ! defined($bfsDepth->[$_]) ||
								abs( $bfsDepth->[$_] - $bfsDepth->[$node] )
											<= $MAX_ANCESTOR_DEPTH_DIFF )
							 } dedup( @{$tree->[$node]} );

			if(@children){
				# add this node to the partial path
				$stackedParents[$node] = 1;
				push2 @partialPath, $node;

				push2 @stack, -$depth;
				push2 @stack, grep { !$stackedParents[$_] } @children;

				$depth++;
			}
		}

		$nodecount = keys %visitCount;
		$edgecount++;
		&$progresser();
	}

	progress_end($nodecount, $edgecount);
	progress_end("$edgecount edges between $nodecount nodes traversed");

	statsByValue( \%visitCount, $termGID, "Count terms which are visited x times" );
	if($DEBUG & DBG_TRAVERSE_NET){
		for(my $i = 1; $i < $termGID; $i++){
			next if !$visitCount{$i};

			if($visitCount{$i} >= 10){
				print $LOG "$i '$terms[$i]': $visitCount{$i} visits, $inheritCount[$i] inherits\n";
			}
		}
	}
}

sub breadthFirst
{
	my %args = @_;

	my $D 			= $args{depth} 			|| 10000;
	my $callback 	= $args{callback} 		|| \&NO_OP;
	my $tree 		= $args{tree} 			|| \@conceptNet;
	my $roots 		= $args{roots};
	my $visited 	= $args{visited} 		|| \@visited;
	my $bfsTree 	= $args{travTree} 		|| \@bfsTree;
	my $bfsHashTree	= $args{travHashTree} 	|| \@bfsHashTree;
	my $bfsDepth	= $args{bfsDepth};
	my $incremental	= $args{incremental};

	my ($parent, $node, @children);

	my @roots;

	print $tee "BFS traverse of the concept net at roots ",
					quoteArray( map { $terms[$_] } @$roots ), ":\n";

	if(!$incremental){
		@$visited 		= (0) x $termGID;
		@$bfsTree 		= map { [] } 1 .. $termGID;
		@$bfsHashTree 	= ();
		@roots = @$roots;
		$visited[0] = 1;

		if($bfsDepth){
			@$bfsDepth = (0);
		}
	}
	else{
		for(@$roots){
			if($visited->[$_]){
				print $tee "warn: root $_ '$terms[$_]' has been visited, skip\n";
			}
			else{
				push @roots, $_;
			}
		}
	}

	my @queue = @roots;

	my ($depth, $lastdepth);

	$depth = 1;		# current depth, the pushed depth will be $depth + 1
	$lastdepth = 1;	# the last pushed depth to the queue
	$parent = 0;

	my %visitCount = ( 0 => 1 );

	my ($nodecount, $edgecount) = ( 0, 0 );
	my $progresser = makeProgresser( vars => [ \$edgecount, \$nodecount ], step => 1000 );

	$sn = 0;

	while(@queue){
		$sn++;

		$node = shift2 @queue;

		if($node < 0){
			$parent = -$node;

			# Following a parent node, @queue is always non-empty
			if($queue[0] < 0){
				$depth = shift2 @queue;
				$depth = - $depth;
			}
			next;
		}

		# for repeated calls of breadthFirst, keep the initial value
		if($bfsDepth && !$bfsDepth->[$node]){
			$bfsDepth->[$node] = $depth;
		}

		$visitCount{$node}++;

		&$callback($node, $parent, $depth);

#		print $DUMP "$terms[$node]\t$terms[$parent]\t$depth\n";

		if(! $bfsHashTree[$parent]->{$node}){
			push @{$bfsTree->[$parent]}, $node;
			$bfsHashTree[$parent]->{$node} = 1;
		}

		if(!isExcluded($node, $parent) && $depth <= $D){
			$visited->[$node] = 1;

			@children = grep { !$visited->[$_] && !$stopped[$_] } dedup( @{$tree->[$node]} );
			if(@children){
				push2 @queue, -$node;

				if($depth + 1 > $lastdepth){
					$lastdepth = $depth + 1;	# update $lastdepth
					push2 @queue, -$lastdepth;
				}

				push2 @queue, @children;
				map { if( !isExcluded($_, $node) ){
							$visited->[ $_ ] = 1;
					  }
					} @children;
			}
		}
		elsif(isExcluded($node, $parent) && $DEBUG & DBG_TRAVERSE_NET){
			# do not set $visited->[$node] = 1. So $node can still be visited
			# under an unexcluding parent in the future
			print $LOG "Node $node ($terms[$node]) excluded under $parent ($terms[$parent]), children not visited\n";
		}

		$edgecount++;
		$nodecount = keys %visitCount;
		&$progresser();

	}

	progress_end($nodecount, $edgecount);
	progress_end("$edgecount edges between $nodecount nodes traversed");
}

# this subroutine is replaced by bfsExhaustAncestors
# the passed graph (the misnomer "$tree") has to be cycle-free.
# otherwise the algorithm will run erroneously without outputting the complete DAG "tree".
# the output is not strictly a tree, because a child could have multiple ancestors
sub bfsExhaustAncestors1
{
	my %args = @_;

	my $tree 				= $args{tree};
	my $roots 				= $args{roots};
	my $ancestorTree 		= $args{ancestorTree};
	my $ancestorInheritor 	= $args{ancestorInheritor};
	my @queue 				= @$roots;
	my $inherited			= $args{inherited};

	my ($parent, $node, @children);

	my @indegree;

	@$ancestorTree = ( { 0 => 0 } );
	@$inherited	= (0) x $termGID;

	my ($nodecount, $edgecount) = ( 0, 0 );

	print $tee "Calculating the indegrees of each node:\n";

	my $progresser = makeProgresser( vars => [ \$edgecount, \$nodecount ], step => 1000 );

	my ($i, $j);

	for($i = 0; $i < $termGID; $i++){
		next if isExcluded($i);

		for $j( @{$tree->[$i]} ){
			$indegree[$j]++;
			$edgecount++;
		}
		$nodecount++;
		&$progresser();
	}
	progress_end($nodecount, $edgecount);

	print $tee "$edgecount edges between $nodecount nodes\n";

	# sanity check. disabled
#	my @orphans;
#	for($i = 1; $i < $termGID; $i++){
#		if($indegree[$i] < 1){
#			push @orphans, $i;
#		}
#	}

#	my @expanded  = (0) x $termGID;
#
#	$expanded[0] = 1;

	print $tee "Breadth-first traverse of the tree:\n";

	my ($depth, $lastdepth);

	$depth = 1;		# current depth, the pushed depth will be $depth + 1
	$lastdepth = 1;	# the last pushed depth to the queue
	$parent = 0;

	$edgecount = $nodecount = 0;

	while(@queue){
		$node = shift2 @queue;
#		$visited->[ abs($node) ] = 1;

		if($node < 0){
			$parent = -$node;

			# Following a parent node, @queue is always non-empty
			if($queue[0] < 0){
				$depth = shift2 @queue;
				$depth = - $depth;
			}
			next;
		}

		# if the indegree of $node is 0, it should have been expanded
		die if $indegree[$node] == 0;

		$indegree[$node]--;

		# it should never happen
		if(&$ancestorInheritor($node, $parent, $depth) == -1){
			print $tee "FATAL: cycle between $node '$terms[$node]' & $parent '$terms[$parent]'\n";
		}

		$edgecount++;

		# wait for the last ancestor
		if($indegree[$node] > 0){
			next;
		}

#		print $DUMP "$terms[$node]\t$terms[$parent]\t$depth\n";
#		push @{$bfsTree->[$parent]}, $node;

		$inherited->[$node] = 1;

		if(!isExcluded($node, $parent)){
			@children = dedup( @{$tree->[$node]} );
			if(@children){
				push2 @queue, -$node;

				if($depth + 1 > $lastdepth){
					$lastdepth = $depth + 1;	# update $lastdepth
					push2 @queue, -$lastdepth;
				}

				push2 @queue, @children;
			}
		}
		elsif(isExcluded($node, $parent) && $DEBUG & DBG_TRAVERSE_NET){
			print $LOG "Node $node ($terms[$node]) excluded, children not visited\n";
		}

		$nodecount++;
		&$progresser();

	}

	progress_end($nodecount, $edgecount);
	progress_end("$edgecount edges between $nodecount nodes traversed");

	print $tee "Sanity check (whether there's residual indegree):\n";

	my $orphanCount = 0;

	# sanity check: no node should be left with indegree > 0, i.e. no orphan
	for($i = 0; $i < $termGID; $i++){
		if($indegree[$i]){
			if($DEBUG & DBG_TRAVERSE_NET){
				print $LOG "ERROR: $i '$terms[$i]': in = $indegree[$i]\n";
				$orphanCount++;
			}
		}
	}

	print $tee "$orphanCount orphans found\n";

}

# the passed graph (the misnomer "$tree") needn't be cycle-free.
# the output is not strictly a tree, because a child could have multiple ancestors
sub bfsExhaustAncestors
{
	my %args = @_;

	my $tree 				= $args{tree};
	my $roots 				= $args{roots};
	my $ancestorTree 		= $args{ancestorTree};
	my $ancestorInheritor 	= $args{ancestorInheritor};
	my @queue 				= @$roots;
	my $bfsDepth			= $args{bfsDepth} || \@bfsDepth;

	my ($parent, $node, @children);

	my @indegree;

	@$ancestorTree = ( { 0 => 0 } );

	@$bfsDepth = (0) x $termGID;

	my ($nodecount, $edgecount) = ( 0, 0 );

	my $progresser = makeProgresser( vars => [ \$edgecount, \$nodecount ], step => 1000 );

	my %visitCount = ( 0 => 1 );

	print $tee "Breadth-first traverse of the tree:\n";

	my ($depth, $lastdepth);

	$depth = 1;		# current depth, the pushed depth will be $depth + 1
	$lastdepth = 1;	# the last pushed depth to the queue
	$parent = 0;

	$sn = 0;

	while(@queue){
		$sn++;

		$node = shift2 @queue;
#		$visited->[ abs($node) ] = 1;

		if($node < 0){
			$parent = -$node;

			# Following a parent node, @queue is always non-empty
			if($queue[0] < 0){
				$depth = shift2 @queue;
				$depth = - $depth;
			}
			next;
		}

		my $inheritStatus = &$ancestorInheritor($node, $parent, $depth);
		# if a cycle is detected, the children of $node will not be expanded
		# i.e., the edge between $node <- $parent is simple discarded
		if($inheritStatus == -1){
			if($DEBUG & DBG_TRAVERSE_NET){
				print $LOG "$sn: CYCLE $node '$terms[$node]' & $parent '$terms[$parent]'\n";
			}
			next;
		}
		# the ancestor list of $node doesn't change. no need to propogate new ancestors
		# to its descendents
		elsif($inheritStatus == 0 && $visitCount{$node}){
			next;
		}

		$edgecount++;

		if(!$bfsDepth->[$node]){
			$bfsDepth->[$node] = $depth;
		}

#		print $DUMP "$terms[$node]\t$terms[$parent]\t$depth\n";
#		push @{$bfsTree->[$parent]}, $node;

		# no matter whether $node is excluded, we count its "expanded" freq
		# if it's excluded, $visitCount{$node} gives how many times it's encountered
		$visitCount{$node}++;

		if(!isExcluded($node, $parent)){
			@children = grep { !$bfsDepth->[$_]
									||
								abs( $bfsDepth->[$_] - $bfsDepth->[$node] )
										<= $MAX_ANCESTOR_DEPTH_DIFF
							 } dedup( @{$tree->[$node]} );

			if(@children){
				push2 @queue, -$node;

				if($depth + 1 > $lastdepth){
					$lastdepth = $depth + 1;	# update $lastdepth
					push2 @queue, -$lastdepth;
				}

				push2 @queue, @children;
			}

		}
		elsif(isExcluded($node, $parent) && $DEBUG & DBG_TRAVERSE_NET){
			print $LOG "Node $node ($terms[$node]) excluded, children not visited\n";
		}

		$nodecount = keys %visitCount;
		&$progresser();

	}

	progress_end($nodecount, $edgecount);
	progress_end("$edgecount edges between $nodecount nodes traversed");

	statsByValue( \%visitCount, $termGID, "Count terms which are visited x times" );
	if($DEBUG & DBG_TRAVERSE_NET){
		for(my $i = 1; $i < $termGID; $i++){
			next if !$visitCount{$i};

			if($visitCount{$i} >= 10){
				print $LOG "$i '$terms[$i]': $visitCount{$i} visits\n";
			}
		}
	}
}

sub addStopterm
{
	my $id;
	my $verbose = 0;

	if($_[0] eq "1"){
		$verbose = shift;
	}

	if($verbose){
		print $tee "Add stop-term ", scalar @_, " terms:\n", quoteArray(@_), "\n";
	}
	else{
		print $LOG "Add stop-term ", scalar @_, " terms:\n", quoteArray(@_), "\n";
		print STDERR "Add stop-term ", scalar @_, " terms\n";
	}

	my $term;

	for(@_){
		next if /^\s*$/;

		$term = decap($_);

		if($stopterm{$term} && $verbose){
			print $tee "'$term' has already been a stop-term. Do nothing.\n";
		}
		else{
			$stopterm{$term} = 1;
			$id = getTermID($term);
			if($id == -1){
				if($verbose){
					print $tee "Warn: '$term' hasn't been in concept net yet\n";
				}
			}
			else{
				$stopped[$id] = 1;
			}
		}
	}
}

sub excludeX
{
	my $id;
	my $verbose = 0;

	if($_[0] eq "1"){
		$verbose = shift;
	}

	if($verbose){
		print $tee "ExcludeX ", scalar @_, " terms:\n", quoteArray(@_), "\n";
	}
	else{
		print STDERR "ExcludeX ", scalar @_, " terms\n";
		print $LOG "ExcludeX ", scalar @_, " terms:\n", quoteArray(@_), "\n";
	}

	my $term;

	for(@_){
		next if /^\s*$/;

		$term = decap($_);

		if($excludedX{$term} && $verbose){
			print $tee "XTerm '$term' has already been excluded, do nothing.\n";
		}
		else{
			$excludedX{$term} = 1;
		}
	}
}

sub exclude
{
	my $id;
	my $verbose = 0;

	if($_[0] eq "1"){
		$verbose = shift;
	}

	if($verbose){
		print $tee "Exclude ", scalar @_, " terms:\n", quoteArray(@_), "\n";
	}
	else{
		if($DEBUG & DBG_INIT_LISTS){
			print STDERR "Exclude ", scalar @_, " terms\n";
			print $LOG "Exclude ", scalar @_, " terms:\n", quoteArray(@_), "\n";
		}
	}

	my @nonexist;

	for(@_){
		next if /^\s*$/;

		$id = getTermID($_);
		if($id < 0){
			push @nonexist, $_;
		}
		elsif($excluded{_}{$id} && $verbose){
			print $tee "Term '$_' has already been excluded, do nothing.\n";
		}
		else{
			$excluded{_}{$id} = 1;
		}
	}

	if(@nonexist && $verbose){
		print $tee "Terms ", quoteArray(@_), " not in the concept net, not excluded\n";
	}
}

sub shortlist
{
	my $list = shift;
	my $n = shift;
	my $suspension = "";

	if($n >= scalar @$list){
		$n = scalar @$list;
	}
	else{
		$suspension = "...";
	}

	return "'" . join("', '", @{$list}[0 .. $n - 1]) . "'" . $suspension;
}

sub exclude4whitelist
{
	my $verbose;
	if($_[0] eq "1"){
		$verbose = shift;
	}
	my $whitelist = shift;

	my ($parent, $pid);
	my @children;
	my @whitelist;
	my @whiteIDs;
	my %whiteIDs;
	my $child;
	my @blackIDs;
	my @blacklist;
	my $n;

	for $parent(keys %$whitelist){
		$pid = getTermID($parent);
		if($pid < 0){
			if($verbose){
				print $tee "Term '$parent' not in the concept net, ignore\n";
			}
			next;
		}
		@whitelist = split /,\s*/, $whitelist->{$parent};
		@whiteIDs = terms2IDs(\@whitelist);
		%whiteIDs = map { $_ => 1 } @whiteIDs;

		@children = dedup( @{$conceptNet[$pid]} );

		@blackIDs = ();

		for $child(@children){
			if(!$whiteIDs{$child}){
				$excluded{$pid}{$child} = 1;
				push @blackIDs, $child;
			}
			else{
				# if a white ID was excluded before, we can include it back here by another "w" command
				$excluded{$pid}{$child} = 0;
			}
		}

		@blacklist = map { $terms[$_] } @blackIDs;

		if($verbose){
			print $tee "$parent:\nInclude ", shortlist(\@whitelist, 2), ", ", scalar @whitelist, " terms\n";
			print $tee "Exclude ", shortlist(\@blacklist, 2), ", ", scalar @blackIDs, " terms\n";
		}
		elsif($DEBUG & DBG_INIT_LISTS){
			print $LOG "$parent:\nInclude ", shortlist(\@whitelist, 2), ", ", scalar @whitelist, " terms\n";
			print $LOG "Exclude ", shortlist(\@blacklist, 2), ", ", scalar @blackIDs, " terms\n";
		}
	}

	if(!$verbose){
		print $tee "Children of ", scalar keys %$whitelist, " terms excluded\n";
	}
}

sub include
{
	my $id;

	print $tee "Include ", scalar @_, " terms:\n", join(", ", @_), "\n";

	for(@_){
		$id = getTermID($_);
		if($id < 0){
			print $tee "Term '$_' not in the concept net, not excluded\n";
		}
		else{
			if( ! $excluded{_}{$id} && ! $stopped[$id] ){
				print $tee "Term '$_' was not excluded nor stopped\n";
				next;
			}
			if($excluded{_}{$id}){
				delete $excluded{_}{$id};
				print $tee "'$_' removed from \%excluded\n";
			}
			if($stopped[$id]){
				$stopped[$id] = 0;
				print $tee "'$_' removed from \@stopped\n";
			}
		}
	}
}

sub setTopAncestors
{
	my ($pNet, $roots) = @_;
	$pNet->[0] = [ @$roots ];
	$edgeTable[0] = { map { $_ => 1 } @$roots };

	print $tee "Set the root of $nameof{$pNet} to: ",
					quoteArray( map { $terms[$_] } @$roots ), "\n";
}

sub enumAncestors($$$$$$$;$)
{
	my ($tree, $rootterms, $ancestorTree, $inheritCount, $depthByBatch,
				$attenuateByBatch, $recAttenuateByBatch, $doExpansion) = @_;
	my @roots = terms2IDs($rootterms);

	setTopAncestors($tree, \@roots);
	@$ancestorTree = ( { 0 => 0 } );
	@$inheritCount = ();
	@$depthByBatch = ();

	my $ancestorInheritor = ancestorInheritor($ancestorTree, $inheritCount, $depthByBatch,
												$attenuateByBatch, $recAttenuateByBatch);

	breadthFirst( tree => $tree, roots => \@roots, bfsDepth => \@bfsDepth,
				 	callback => $ancestorInheritor );

#	my $root;
#
#	my $inc = 0;
#	for $root(@roots){
#		breadthFirst( tree => $tree, roots => [ $root ], bfsDepth => \@bfsDepth,
#					 	callback => ancestorInheritor($ancestorTree), incremental => $inc );
#		$inc++;
#	}

	if($doExpansion){
		dfsExpandAncestors( tree => $tree, roots => [ @roots ], travTree => \@dfsTree,
							bfsDepth => \@bfsDepth, ancestorTree => $ancestorTree,
							ancestorInheritor => $ancestorInheritor );
	}

#	# using breadth first
#	bfsExhaustAncestors( tree => $tree, roots => [ @roots ], ancestorTree => $ancestorTree,
#							bfsDepth => \@bfsDepth );

	if($DEBUG & DBG_CHECK_ROOT_ANCESTOR){
		my $i;
		for($i = 1; $i < $termGID; $i++){
			next if !$bfsDepth[$i];

			if(! exists $ancestorTree->[$i]->{0} ){
				print $tee "Warn: $i - $terms[$i] has no root ancestor!\n";
			}
		}
	}
}

sub dumpChildren
{
	my %args = @_;

	my ($rootterms, $ancestorTree, $inheritCount, $depthByBatch, $attenuateByBatch, $recAttenuateByBatch,
			$interestedSubtree, $dumpFilename, $D);

	$rootterms    			= $args{rootterms};
	$ancestorTree 			= $args{ancestorTree} 			|| \@ancestorTree;
	$inheritCount			= $args{inheritCount} 			|| \@inheritCount;
	$depthByBatch			= $args{depthByBatch} 			|| \@depthByBatch;
	$attenuateByBatch		= $args{attenuateByBatch} 		|| \@attenuateByBatch;
	$recAttenuateByBatch	= $args{recAttenuateByBatch}	|| \@recAttenuateByBatch;
	$interestedSubtree  	= $args{interestedSubtree} 		|| \@subtree;

	my $DUMP;

	print $tee "Dumping concept net rooted at ", quoteArray(@$rootterms);

	if($args{depth}){
		$D = $args{depth};
		print $tee ", max $D levels";
	}
	else{
		$D = 10000;
	}

	my @roots = terms2IDs($rootterms);
	if(!@roots){
		print STDERR "\n", quoteArray(@$rootterms), " not found in the concept net\n";
		return;
	}

	if($args{dumpFilename}){
		$dumpFilename = getAvailName( $args{dumpFilename} );
		if(!open_or_warn($DUMP, "> $dumpFilename")){
			return;
		}
		else{
			print $tee ", into '$dumpFilename'.";
		}
	}
	else{
		$DUMP = \*STDERR;
	}

	print $tee "\n";

	my @tempVisited;

	# only show a twig, don't change the whole tree
	if($args{treeview}){
		dfsPreorder( depth => $D,
					callback =>
						sub
						{
							my ($node, $parent, $depth) = @_;
							print $DUMP "  " x ($depth - 1), "$terms[$node]\n";
						},
					roots => [ @roots ], visited => \@tempVisited
				   );
	}
	# assume we traverse the whole tree in this case. Set the top ancestors under the ROOT
	else{
		if(! $ancestorTree){
			die "'ancestorTree' not provided for dumpChildren()";
		}

		setTopAncestors(\@conceptNet, \@roots);
		@$ancestorTree = ( { 0 => 0 } );
		@$inheritCount = ();
		@$depthByBatch = ();

		my $ancestorInheritor = ancestorInheritor($ancestorTree, $inheritCount,
									$depthByBatch, $attenuateByBatch, $recAttenuateByBatch);

		breadthFirst( depth => $D, roots => [ @roots ], visited => \@visited,
						bfsDepth => \@bfsDepth, callback => $ancestorInheritor );

		my ($i, $j);
		my @isAncestors;

		my $edgecount = 0;
		my $nodecount = 0;
		my $progresser = makeProgresser( vars => [ \$edgecount, \$nodecount ], step => 1000 );

		@$interestedSubtree = map { [] } 1 .. $termGID;
		@revConceptNet = map { [] } 1 .. $termGID;

		$sizeof{$interestedSubtree} = 0;
		$sizeof{\@revConceptNet} = 0;

		for($i = 0; $i < $termGID; $i++){
			# if $i is visited, then it's not a stopterm (not stopped). otherwise it won't be visited
			# in the bfs traverse. So no need to check $stopped[$i] here
			if( $visited[$i] && ! isExcluded($i) ){
				for $j( @{$conceptNet[$i]} ){
					if( !$stopped[$j] ){
						print $DUMP "$terms[$j]\t$terms[$i]\t$bfsDepth[$i]\n";

						addEdgeByID($interestedSubtree, $j, $i);
						addEdgeByID(\@revConceptNet, $i, $j);

						$edgecount++;
					}
				}
				$nodecount++;
				&$progresser();
			}
		}
		progress_end($nodecount, $edgecount);

		print $tee "$edgecount edges between $nodecount nodes dumped\n";

#		enumAncestors($interestedSubtree, $rootterms, $ancestorTree, $inheritCount, $depthByBatch);
	}
}

sub ancestorInheritor
{
	my ($pAncestorTree, $pInheritCount, $pDepthByBatch, $pAttenuateByBatch, $pRecAttenuateByBatch) = @_;

	return
	sub
	{
		# the passed-in depth is simply ignored
		my ($node, $parent, $depth) = @_;
		my $ancestor;

		# a cycle is detected
		if($pAncestorTree->[$parent]->{$node}){
			return -1;
		}

		my $batchNum = $pInheritCount->[$node]++;

		my ($depth_batch, $batch);
		my $maxDepthThisBatch = -1;

		my @newAncestors;
		my $addSelf = 0;

		# not form a cycle yet. $node inherits ancestors from $parent
		# if an ancestor has been included, the depth won't be updated
		# because the older depth is always <= the newer depth
		while( ($ancestor, $depth_batch) = each %{$pAncestorTree->[$parent]} ){
			($depth, $batch) = WWSplit($depth_batch);
			if(! exists $pAncestorTree->[$node]->{$ancestor}){
				# increase depth by 1
				$depth += 1;
				# set the batch num
				$depth_batch = combineWW($depth, $batchNum);
				$pAncestorTree->[$node]->{$ancestor} = $depth_batch;

				push @newAncestors, [ $ancestor, $depth, $depth + $bfsDepth[$ancestor], $batch ];

				if($depth + $bfsDepth[$ancestor] > $maxDepthThisBatch){
					$maxDepthThisBatch = $depth + $bfsDepth[$ancestor];
				}
			}
		}

		# first inheritance
		if(! exists $pAncestorTree->[$node]->{$node}){
			# depth of $node is 0, needless to set the higher word
			$pAncestorTree->[$node]->{$node} = $batchNum;
			$addSelf = 1;
		}
		$pDepthByBatch->[$node]->[$batchNum] = $maxDepthThisBatch;
											# $maxDepthThisBatch should never be bigger than $bfsDepth
											# though, I cap it to 1. just in case
		if($maxDepthThisBatch > 0){
			$pAttenuateByBatch->[$node]->[$batchNum] = min( 1,
									$pDepthByBatch->[$node]->[0] / $maxDepthThisBatch );
			$pRecAttenuateByBatch->[$node]->[$batchNum] = max( 1,
									$maxDepthThisBatch / $pDepthByBatch->[$node]->[0] );
		}

		# ancestor count doesn't change, i.e., no new ancestor is added
		if(@newAncestors == 0 && !$addSelf){
			return 0;
		}

		if($batchNum > 1 && $DEBUG & DBG_CHECK_INHERIT_DEPTH_RATIO){
			if( $maxDepthThisBatch >= $SUSPICIOUS_INHERIT_DEPTH &&
					$bfsDepth[$node] * $SUSPICIOUS_INHERIT_DEPTH_RATIO < $maxDepthThisBatch ){

				my @batch1Ancestors;
				while( ($ancestor, $depth_batch) = each %{$pAncestorTree->[$node]} ){
					($depth, $batch) = WWSplit($depth_batch);
					# first batch has number 0
					if($batch == 0){
						push @batch1Ancestors, [ $ancestor, $depth, $depth + $bfsDepth[$ancestor], $batch ];
					}
				}

				# sort ascendingly by depth
				@batch1Ancestors 	= sort { $a->[3] <=> $b->[3] || $a->[1] <=> $b->[1] } @batch1Ancestors;
				@newAncestors 		= sort { $a->[3] <=> $b->[3] || $a->[1] <=> $b->[1] } @newAncestors;

				my $ancestorTuple;
				print $LOG "Suspicious inheritance: ";
				print $LOG join( ", ", map {
										my ($ancestor, $updepth, $downdepth, $batch) = @$_;
										"$ancestor($updepth,$downdepth,$batch) '$terms[$ancestor]'"
									} @newAncestors
							   );
				print $LOG ". Batch 1: ";
				print $LOG join( ", ", map {
										my ($ancestor, $updepth, $downdepth, $batch) = @$_;
										"$ancestor($updepth,$downdepth,$batch) '$terms[$ancestor]'"
									} @batch1Ancestors );
				print $LOG "\n";
			}
		}

		return 1;
	};
}

sub dumpAncestors
{
	my %args = @_;

	my ($rootterm, $ancestorTree, $dumpFilename, $simpleMode, $doPrintFreq, $uplevel);

	$rootterm 		= $args{rootterm};
	$ancestorTree 	= $args{ancestorTree};
	$simpleMode		= $args{simpleMode};
	$doPrintFreq	= $args{printFreq};
	$uplevel		= $args{uplevel} || 10;

	print $tee "Dumping ancestors upwards from '$rootterm'";

	my $root = getTermID($rootterm);
	if($root == -1){
		print $tee "\n'$rootterm' doesn't exist\n\n";
		return;
	}

	if(!$ancestorTree){
		print $tee "\nancestorTree not provided, abort\n";
		return;
	}

	if($doPrintFreq){
		if(!$freqs[$root]){
			print $tee "Term '$terms[$root]' is never matched. Freqs won't be printed.\n";
			$doPrintFreq = 0;
		}
	}

	my $parent = -1;
	my $id = $root;

	my $DUMP;

	if($args{dumpFilename}){
		$dumpFilename = getAvailName( $args{dumpFilename} );
		if(!open_or_warn($DUMP, "> $dumpFilename")){
			return;
		}
		else{
			print $tee " into '$dumpFilename'.";
		}
	}
	else{
		$DUMP = \*STDERR;
	}

	print $tee "\n";

	# depth is on the higher word, so this sorts by the depth first, then by the batch num
	my @ancestors = sort { $ancestorTree->[$root]->{$b} <=> $ancestorTree->[$root]->{$a} }
							keys %{$ancestorTree->[$root]};

	if($uplevel > 0 && @ancestors > $uplevel){
		@ancestors = @ancestors[ $#ancestors - $uplevel + 1 .. $#ancestors ];
	}

#	while($id > 0){
#		push @path2root, $id;
#		$id = (keys %{$ancestorTree->[$id]})[0];
#	}

	my $depth;
	my $batch;

	for $id(@ancestors){
		($depth, $batch) = WWSplit( $ancestorTree->[$root]->{$id} );

		if(!$doPrintFreq){
			print $DUMP "$depth($batch): $id - $terms[$id]\n";
			if(!$simpleMode){
				print $DUMP "\t", join( ", ", map { $terms[$_] } @{$conceptNet[$id]} ), "\n";
			}
		}
		else{
			print $DUMP "$depth($batch): $id - $terms[$id], ", definedOr0($freqs[$id], 4), "\n";
			if(!$simpleMode){
				print $DUMP "\t", join( ", ",
								map { "$terms[$_] - " . definedOr0($freqs[$_], 4) }
								sort { definedOr0($freqs[$b]) <=> definedOr0($freqs[$a]) } @{$conceptNet[$id]}
									), "\n";
			}
		}
	}

	print $tee "\n";
}

sub listUniqueChildren
{
	my ($conceptNet, $ancestorTree, $term) = @_;
	my $id = getTermID($term);
	if($id == -1){
		print STDERR "'$term' doesn't exist\n";
		return;
	}
	if(! $visited[$id]){
		print STDERR "'$term' is not visited, no valid child\n";
		return;
	}

	print STDERR "Unique children:\n";

	my $uniqChildrenCount = 0;
	my @parents;
	my $ancestorList;

	my $child;
	for $child( @{$conceptNet->[$id]} ){
		next if ! $visited[$child];

		$ancestorList = $ancestorTree->[$child];
		next if ! $ancestorList->{$id} || higherword($ancestorList->{$id}) != 1;
												  # depth == 1
		@parents = grep { higherword($ancestorList->{$_}) == 1 } keys %$ancestorList;
		if(@parents == 1){
			print STDERR "$child: $terms[$child]\t", definedOr0($freqs[$child]), "\n";
		}
	}
}

sub terms2IDs
{
	my ($terms, $abortAtError) = @_;
	my @roots = map { getTermID($_) } @$terms;

	my $i;
	for($i = 0; $i < @roots; $i++){
		if($roots[$i] == -1){
			if($abortAtError){
				print $tee "'$terms->[$i]' doesn't exist in the concept net, abort\n";
				return;
			}
		}
	}

	return grep { $_ != -1 } @roots;
}

=pod
sub checkCycle
{
	my @dfsRevTravTree;

	my @roots = terms2IDs(\@_, 1);
	return if !@roots;

	dfsPostorder(depth => 10000, roots => @roots, visited => \@visited);

	return $isCyclic;
}
=cut

sub tokenIDs2words
{
	my ($lemmaIDs, $tokenIDs) = @_;
	
	return map { $lemmaCache[ $lemmaIDs->[$_] ]->[0] } @$tokenIDs;
}

sub leastCommonSubsumer
{
	my ($ancestorTree, $i, $j, $D) = @_;

	if($i == -1 || $j == -1){
		print STDERR "Invalid term ID is given\n";
		return -1;
	}

	my $ancestorList1 = $ancestorTree->[$i];
	my $ancestorList2 = $ancestorTree->[$j];
	my @commonSubsumers = intersectHash( $ancestorList1, $ancestorList2 );

	my %commonSubsumers;
	
	my $recAttenuateByBatch1 	= $recAttenuateByBatch[$i];
	my $recAttenuateByBatch2 	= $recAttenuateByBatch[$j];
	my $attenuateByBatch1 		= $attenuateByBatch[$i];
	my $attenuateByBatch2 		= $attenuateByBatch[$j];

	my ($subsumer, $depthSum, $attenDepthSum, $batchSum);
	my @leastDepthPair	= ();
	my $leastDepthSum	= 10000;
	my $leastAttenDepthSum = 10000;
	my $leastBatchSum 	= 10000;
	my $lcs 			= -1;
	my $depths_batches;
	my $attenuation = 1;
	
	my ($dep1, $bat1, $dep2, $bat2);

	for $subsumer(@commonSubsumers){
		($dep1, $bat1) = WWSplit( $ancestorList1->{$subsumer} );
		($dep2, $bat2) = WWSplit( $ancestorList2->{$subsumer} );
		$depthSum = $dep1 + $dep2;
		
		if( $D && $depthSum > $D ){
			next;
		}
		if($USE_FREQ_PASSUP_ATTENUATION){
			$dep1 *= $recAttenuateByBatch1->[$bat1];
			$dep2 *= $recAttenuateByBatch2->[$bat2];
			$attenDepthSum = $dep1 + $dep2;
			
			if( $depthSum < $leastDepthSum
							|| 
				( $depthSum == $leastDepthSum ) && ( $attenDepthSum < $leastAttenDepthSum ) 
			){
				$lcs = $subsumer;
				$leastDepthSum = $depthSum;
				$leastAttenDepthSum = $attenDepthSum;
				$attenuation = $attenuateByBatch1->[$bat1] * $attenuateByBatch2->[$bat2];
				@leastDepthPair = ($dep1, $dep2);
			}
		}
		else{
			$batchSum = $bat1 + $bat2;
			if($depthSum < $leastDepthSum){
				$lcs = $subsumer;
				$leastDepthSum = $depthSum;
				@leastDepthPair = ($depths_batches->[0], $depths_batches->[2]);
				$leastBatchSum = $batchSum;
			}
			elsif($depthSum == $leastDepthSum){
				if($batchSum < $leastBatchSum){
					$lcs = $subsumer;
					@leastDepthPair = ($depths_batches->[0], $depths_batches->[2]);
					$leastBatchSum = $batchSum;
				}
			}
		}
	}

	if(! $D && $lcs == -1){
		# it should never happen: at least the "CONCEPT_NET_ROOT" is the common ancestor
		die "No common ancestor for '$terms[$i]' & '$terms[$j]'!";
	}
	return ($lcs, $leastDepthSum, $attenuation, @leastDepthPair);
}

# return a hash of key1 => [ key2,  depth_from_key1_to_key2 ]
# %mergeMap includes all terms (keys) in %$pPosting2weight
sub mergeNearbyTerms
{
	my ($ancestorTree, $pPosting2weight, $MaxNearbyTermsDepthDiff) = @_;

	my ($i, $j);
	my %posting2weight = %$pPosting2weight;
	my @postings = keys %posting2weight;
	my $N;
	my ($lcs, $leastDepth, $attenuation);
	my %outPairs;
	my %mergeMap;
	my ($p1, $p2, $w1, $w2, $dep1, $dep2);
	my %lcsCache;

	my $maxDepthDiff = 1;
	my $leastWeightRatio;

	$attenuation = 1;
	
	while($maxDepthDiff <= $MaxNearbyTermsDepthDiff){
		# $w1/$w2 should be no less than this ratio. otherwise they won't be merged
		# it's to avoid the merge being misled by insignificant match terms
		# if the depth diff = 1, $leastWeightRatio = 0, that means $p1 and $p2 will always be merged
		# if the depth diff = 2, $leastWeightRatio = 1/2, only merge when 1/2 <= $w1/$w2 <=2
		$leastWeightRatio = 1 - 1 / $maxDepthDiff;

		for($i = 0; $i < @postings; $i++){
			$p1 = $postings[$i];
			next if !$p1;
			$w1 = $posting2weight{$p1};

			# the term is almost a most general one, so merging it doesn't make much sense
			next if $bfsDepth[$p1] < $MIN_ANCESTOR_DEPTH;

			for($j = 0; $j < @postings; $j++){
				next if $i == $j;
				$p2 = $postings[$j];
				next if !$p2;
				$w2 = $posting2weight{$p2};

				next if $bfsDepth[$p2] < $MIN_ANCESTOR_DEPTH;
				next if $outPairs{"$p1,$p2"};

				if($p1 == $p2){
					$postings[$j] = undef;
					next;
				}

				if($lcsCache{"$p1,$p2"}){
					($lcs, $leastDepth, $attenuation, $dep1, $dep2) = @{ $lcsCache{"$p1,$p2"} };
				}
				else{
					# $leastDepth, $dep1, $dep2 has been weighted by $revAttenuation in leastCommonSubsumer()
					($lcs, $leastDepth, $attenuation, $dep1, $dep2) = 
								leastCommonSubsumer($ancestorTree, $p1, $p2, $MaxNearbyTermsDepthDiff);
				}
				if( $lcs >= 0 && $bfsDepth[$lcs] >= $MIN_ANCESTOR_DEPTH &&
						ratio($w1, $w2) >= $leastWeightRatio ){
					if($leastDepth <= $maxDepthDiff){
						if($lcs != $p1){
							$mergeMap{$p1} = [ $lcs, $dep1 ];
						}
						if($lcs != $p2){
							$mergeMap{$p2} = [ $lcs, $dep2 ];
						}
						$postings[$i] = $lcs;
						$postings[$j] = undef;
						# the weight of $lcs is the sum of weights of $p1 and $p2
						$posting2weight{$lcs} = $w1 + $w2;
						# restart the outer loop
						$i--;
						last;
					}
					# merge in a future round
					$lcsCache{"$p1,$p2"} = [ $lcs, $leastDepth, $attenuation, $dep1, $dep2 ];
				}
				else{
					$outPairs{"$p1,$p2"} = 1;
					$outPairs{"$p2,$p1"} = 1;
				}
			}
		}
		$maxDepthDiff++;
	}

	my %mergeMap2;
	my $totalDepth;
	
	for $p1(keys %posting2weight){
		$p2 = $p1;
		$totalDepth = 0;
		while($mergeMap{$p2}){
			$totalDepth += $mergeMap{$p2}->[1];
			$p2 = $mergeMap{$p2}->[0];
		}
		# if $p1 doesn't exist in %mergeMap, $p1 'merges' to itself
		$mergeMap2{$p1} = [ $p2, $totalDepth ];
	}

	return %mergeMap2;
}

# author list is absent here
sub addFreqs($$)
{
	my ( $pTermIDs, $pFreqs ) = @_;

	# null matching result
	return if !$pTermIDs;

	my $i;
	for($i = 0; $i < @{$pTermIDs}; $i++){
		addFreqAndAuthors(\@ancestorTree, $pTermIDs->[$i], $pFreqs->[$i]);
	}
}

our $MCConsistent = 1;

sub addFreqAndAuthors($$$;$$)
{
									# author list that uses this term. To be added to @terms2authorIDs
	my ($ancestorTree, $termID, $freq, $pAuthorIDs, $pRefAuthorCount) = @_;
												# count of authors who refer to terms (any term), 
												# for being shown in a progress bar

	if($freq >= $LEAST_COUNTABLE_MATCH_SCORE){
		$addedFreqSum += $freq;
		$addedCountableFreqCount++;
	}
	
	my $oldfreq = $freqs[$termID] || 0;

	my $attenFreq;
	
	my ($depth, $batch, $depth_batch);

	my $batchDepth;
	my $bfsdepth = $bfsDepth[$termID];
	my $ancestorID;
	my $authorID;
	
	if($bfsdepth != $depthByBatch[$termID]->[0] && $DEBUG & DBG_TRACK_ADD_FREQ){
		print $LOG "$terms[$termID]: batch 0 depth: $depthByBatch[$termID]->[0] != bfsDepth $bfsdepth\n";
	}

	# $termID is in %{$ancestorTree->[$termID]}, with $depth 0
	while( ($ancestorID, $depth_batch) = each %{$ancestorTree->[$termID]} ){
		($depth, $batch) = WWSplit($depth_batch);
		
		if( $depth > 0 && $USE_FREQ_PASSUP_ATTENUATION ){
			$attenFreq = $freq * ( $attenuateByBatch[$termID]->[$batch] ** $depth );
		}
		else{
			$attenFreq = $freq;
		}
		
		$freqs[$ancestorID] += $attenFreq;
		
		# only add authors to itself and ancestors one level higher. 
		# coz in titleSetToVector()->compactConceptVector(), it only does one level generalization
		# if populating upwards limitlessly, a general term will have too many authors referring to it
		# this doesn't reflect the actual user number of it (as well as its discriminating power)
		# If we don't do generalization in titleSetToVector(), we don't need to count the authors in
		# for ancestors at all
		if($pAuthorIDs && $depth <= 1 && $attenFreq >= $LEAST_COUNTABLE_MATCH_SCORE){
			for $authorID(@$pAuthorIDs){
				$term2authorIDs[$ancestorID]{$authorID}++;
				# $authorID is a newly referring author for certain term 
				# an author may be counted more than once in this number, if he refers to different terms
				if($term2authorIDs[$ancestorID]{$authorID} == 1){
					$$pRefAuthorCount++;
				}
			}
			$gen1freqs[$ancestorID] += $attenFreq;
		}
	}

	if($DEBUG & DBG_TRACK_ADD_FREQ){
		print $LOG "$terms[$termID]: freq $oldfreq + $freq = $freqs[$termID]\n";
	}

	$MC += $freq;

	if($MC != $freqs[0] && $MCConsistent){
		$MCConsistent = 0;
		print $LOG "INCONSISTENCY: $terms[$termID]: freq $freq, \$MC $MC != \$freqs[0] $freqs[0]\n";
	}
}

sub cleanTerm
{
	for(@_){
		s/_/ /g;
		s/^[A-Z](\w+:)+(?=\S)//;
		if( s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge ){
			s/\xE2\x80\x93/ /g;
		}
		s/^\s+|\s+$//g;
		s/(?<!-)-(?!-)/ /g;
	}
}

our @power2 = (0);
for my $i(0 .. $MATCH_TERM_WINDOW){
	for my $j( (1 << $i) .. (1 << ($i+1)) - 1){
		$power2[$j] = 1 << $i;
	}
}

our @bit1count = (0);
for my $i(0 .. $MATCH_TERM_WINDOW){
	for my $j( (1 << $i) .. (1 << ($i+1)) - 1){
		$bit1count[$j] = scalar bitmap2nums($MATCH_TERM_WINDOW, $j);
	}
}

sub initPostingCache
{
	print $tee "Initialize posting caches of frequent bigrams...\n";
	
	if(! loadGramFile(\%highFreqBigrams, "$NLPUtil::homedir/bigram[a-m].csv", 
				$CACHE_BIGRAM_POSTING_LEAST_FREQ, 1) ){
		return 0;
	}
	if(! loadGramFile(\%highFreqBigrams, "$NLPUtil::homedir/bigram[n-z].csv", 
				$CACHE_BIGRAM_POSTING_LEAST_FREQ, 1) ){
		return 0;
	}
	
	my $bigram;
	my ($w1, $w2);
	my $key;
	
	my $highFreqBigramCount = scalar keys %highFreqBigrams;
	print $tee "Preload postings of $highFreqBigramCount high-freq bigrams:\n";
	
	my $bigramCount = 0;
	my $cachedBigramCount = 0;
	my $postingCount = 0;
	
	my $progresser = makeProgresser( vars => [ \$cachedBigramCount, \$bigramCount ], step => 100 );
	
	for $bigram(keys %highFreqBigrams){
		($w1, $w2) = split / /, $bigram;
		if( ($w1 cmp $w2) <= 0){
			$key = $bigram;
		}
		else{
			$key = "$w2 $w1";
		}
		$bigramCount++;
		
		# if the key with two words exchanged has been cached
		next if $postingCache{$key};
		
		$postingCache{$key} = [ intersect( $invTable{$w1}, $invTable{$w2} ) ];
		
		$cachedBigramCount++;
		$postingCount += scalar @{ $postingCache{$key} };
		
		&$progresser();
	}
	
	progress_end("$cachedBigramCount out of $bigramCount bigrams are cached");
	
	return $cachedBigramCount;
}

sub fetchPostingCache
{
	my ($w1, $w2) = @_;
	my $key;
	
	if( ($w1 cmp $w2) <= 0){
		$key = "$w1 $w2";
	}
	else{
		$key = "$w2 $w1";
	}
	
	return $postingCache{$key};
}
	
sub matchPhrase($$$$$$$)
{
	my ( $words, $phraseLemmaIDs, $stopwordGapNums, $stopwordGapWeights, 
			$postingSets, $maxsets, $gapDiscounts ) = @_;

	my $fixword;
	my $word;

	my $N = @$words;

	my ($pos, $j);

	my $complement;
	my $highestBit;

	my $singleton;
	my $fixSingleton;

	my $postingSet;
	my $fixPostings;

	if($N > $MATCH_TERM_WINDOW){
		die "Too many words: '@$words' passed in (shouldn't exceed $MATCH_TERM_WINDOW)";
	}

	@$maxsets = ();
	@$postingSets = ();
	@$gapDiscounts = ();
	
	my %wordcount;
	for $word(@$words){
		# this word appears twice in @$words, forbidden, so return empty result
		if($wordcount{$word}){
			return;
		}
		$wordcount{$word}++;
	}

	$fixword = $words->[-1];

	if(!$invTable{$fixword} || !$gUnigrams{$fixword}){
		return;
	}

	# the last word has to appear in the term
	$fixSingleton = 1 << $N - 1;
	$postingSets->[ $fixSingleton ] = $fixPostings = $invTable{$fixword};

	my $postingDomain;

	for $pos(0 .. $N - 2){
		$word = $words->[$pos];

		next if !$invTable{$word} || !$gUnigrams{$word};

		$postingDomain = fetchPostingCache($word, $fixword);
		if(! $postingDomain){
			$postingDomain = [ intersect($invTable{$word}, $fixPostings) ];
		}
		else{
			$postingCacheHitCount++;
		}
			
		next if !@$postingDomain;

		$singleton = 1 << $pos;

		for $j( (1 << $pos) .. (1 << ($pos + 1)) - 1 ){
			$complement = $j - $singleton;
			if($complement == 0){
				$postingSets->[$j + $fixSingleton] = $postingDomain;
			}
			else{
				$complement += $fixSingleton;
				if($postingSets->[$complement] && @{ $postingSets->[$complement] }){
					$postingSets->[$j + $fixSingleton] = [ intersect($postingDomain, $postingSets->[$complement]) ];
#					if(! @{ $postingSets->[$j + $fixSingleton] }){
#						push @$maxsets, $complement;
#					}
				}
				else{
					$postingSets->[$j + $fixSingleton] = [];
				}
			}
		}
	}

	my @supersets;
	my $superset;
	my $covered;
	my %hasCovableMatch;

	my @indices;
	# the total count of stop word gaps in the phrase in question
	my $stopwordGapTotalNum;
	# the total count of stop word gaps in the phrase in question
	my $stopwordGapTotalWeight;
	my $nonstopCount;
	my $gapDiscount;
	my ($i, $k, $begin, $end);
	my @snipLemmaIDs;
	
	for( $j = (1 << $N) - 1; $j >= $fixSingleton; $j-- ){
		next if ! $postingSets->[$j] || ! @{ $postingSets->[$j] };

		# the count of missed non-stop words. e.g. "image compression" in "image denoising and compression"
		# $nonstopCount = 1 (denoising), $stopwordGapTotalNum = 1 (and)
		$nonstopCount = 0;
		$stopwordGapTotalNum = 0;
		$stopwordGapTotalWeight = 0;
		@indices = bitmap2nums($MATCH_TERM_WINDOW, $j);
		@snipLemmaIDs = @{$phraseLemmaIDs}[@indices];
		
		for($i = 1; $i < @indices; $i++){
			$begin = $indices[ $i - 1 ];
			$end = $indices[ $i ];
			$nonstopCount += $end - $begin - 1;
			for($k = $begin + 1; $k <= $end; $k++){
				$stopwordGapTotalNum += $stopwordGapNums->[$k];
				$stopwordGapTotalWeight += $stopwordGapWeights->[$k];
			}
		}
		if( $nonstopCount * 2 + $stopwordGapTotalWeight * 1.5 > 1.3 * scalar @indices ){
			next;
		}
		$gapDiscount = 1 - ( $nonstopCount * 2 + $stopwordGapTotalWeight * 1.5 ) 
								/ ( 1 + 1.3 * scalar @indices );
		
		$covered = 0;

		for $superset(@$maxsets){
			# the set corresp to $j is covered by the set corresp to $superset
			if( ($j & $superset) == $j &&
						# check of $bit1count[$j] < 2 is useless? since $j is covered by $superset
						# then it contains at least two words
						( $bit1count[$j] < 2 || $hasCovableMatch{$superset} ) ){
				$covered = 1;
				last;
			}
		}

		next if $covered;

		# it's a maximal set
		push @$maxsets, $j; #[ bitmap2nums($j) ];
		push @$gapDiscounts, $gapDiscount;
		
		# check whether this match is eligible to cover a subset query match
		# if a set of query word has a perfect matching term, then this set could cover its subset
		# otherwise, we still need its subsets and find their matching terms
		if($bit1count[$j] <= 2){
			$hasCovableMatch{$j} = 1;
		}
		else{
			my $posting;
			for $posting( @{ $postingSets->[$j] } ){
#				# perfect match. it's not accurate (e.g. query has 3 words,
#				# 2 words matches the main part (3 words), and 1 query word matches the context
#				# the above case rarely happens, so ignored during the training phase
#				if( $termContextStart[$posting] <= $bit1count[$j] ){
#					$hasCovableMatch{$j} = 1;
#					last;
#				}
				if( subtractSet( \@snipLemmaIDs, $termMainTokens[$posting] ) == 0 ){
					$hasCovableMatch{$j} = 1;
					last;
				}
			}
		}
	}

}

# record  ( weight, token_indices ) pairs. need ->[0] to access weight only
sub recordBestMatches($$$$)
{
	my ($pMaxMatchScores, $pTermIDs, $pFreqs, $tokenIndices) = @_;

	my $id;
	my $i;
	my $freq;

	# null matching result
	return if !$pTermIDs;

	for($i = 0; $i < @{$pTermIDs}; $i++){
		$id = $pTermIDs->[$i];
		$freq = $pFreqs->[$i];
		if($freq > 0){
			if(! exists $pMaxMatchScores->{$id}
							||
				  $freq > $pMaxMatchScores->{$id}->[0]){
				$pMaxMatchScores->{$id} = [ $freq, $tokenIndices ];
			}
		}
	}
}

# add the scores of a title match to the accumulative scores. 
# in contrast with recordBestMatches(), %$pAccumuMatchScores only keeps the $freq, no $tokenIndices
sub addMatchScores($$$)
{
	my ( $pAccumuMatchScores, $pTermIDs, $pFreqs ) = @_;

	my $id;
	my $i;
	my $freq;

	# null matching result
	return if !$pTermIDs;

	for($i = 0; $i < @{$pTermIDs}; $i++){
		$id = $pTermIDs->[$i];
		$freq = $pFreqs->[$i];
		$pAccumuMatchScores->{$id} += $freq;
	}
}

our $PERFECT_MATCH_LEAST_SCORE = 0.7;
our $SIGNIFICANT_MATCH_LEAST_SCORE = 0.5;
our $ALL_BAD_MATCHES_DISCOUNT = 0.5;

sub distributeMatches($$$$$)
{
	my ($ancestorTree, $pPostingSet, $pMatchWeightSet, $maxset, $weightThres) = @_;

	my ($posting, $mappedPosting);
	my $i;
	my $score;
	my @freqDistro;
	my %origPostings;
	my %origFreqs;
	my $scoreSum;
	my @postingSet;
	my @freqDeltaSet;
	my %selPostings;
	
	$weightThres ||= 0.01;

	if($DEBUG & DBG_MATCH_TITLE){
		print $LOG "Weight thres before normalization: $weightThres\n";
	}
	
	my @perfectPostings;
	my $perfectPosting;
	my $countedPostingScoreSum = 0;
	
	# There could be more than 1 perfect match. 
	# E.g. "Memetic algorithm" and "Memetic algorithms (Memetic algorithm)"
	# But with the strategy of filtering out those terms whose mains and contexts are the same,
	# this seems no longer a problem
	for($i = 0; $i < @$pPostingSet; $i++){
		$posting = $pPostingSet->[$i];
		$score = $pMatchWeightSet->[$i];
		if($score >= $weightThres){
			if($score == 1){
				push @perfectPostings, $posting;
			}
			else{
				$selPostings{$posting} = $score;
				$countedPostingScoreSum += $score;
			}
		}
	}

	my ($perfectPostingScore, $scaledScoreSum, $scaleDown);
	my %perfectPostings;
	
	# Matching score NEVER SCALE UP
	if( @perfectPostings ){
		# the other posting scores don't need scale.
		if( $countedPostingScoreSum <= 1 - $PERFECT_MATCH_LEAST_SCORE ){
			
			# if there is more than 1 perfectly matched posting, distribute the matching score
			# evenly among them. I guess at most there'd be 2 perfectly matched postings
			# Later mergeNearbyTerms() would probably merge them back to one,
			# since they should be a parent-child pair
			for $perfectPosting( @perfectPostings ){
				$perfectPostings{$perfectPosting} = ( 1 - $countedPostingScoreSum ) / @perfectPostings;
			}
		}
		else{
			$scaledScoreSum = 1 - $PERFECT_MATCH_LEAST_SCORE;
			$scaleDown = $scaledScoreSum / $countedPostingScoreSum;
			
			for $posting(keys %selPostings){
				$selPostings{$posting} *= $scaleDown;
			}

			# scale the perfect match to $PERFECT_MATCH_LEAST_SCORE, and others to be summed to 1 - ...
			for $perfectPosting( @perfectPostings ){
				$perfectPostings{$perfectPosting} = $PERFECT_MATCH_LEAST_SCORE / @perfectPostings;
			}
		}
	}
	else{
		# No perfect match. The sum of imperfect matching scores is scaled to 1
		if($countedPostingScoreSum > 1){
			$scaleDown = 1 / $countedPostingScoreSum;
			for $posting(keys %selPostings){
				$selPostings{$posting} *= $scaleDown;
			}
		}
	}
	
#	no longer uses the exponential normalization. 
#   it doesn't broaden weight differences, but shrinks them! >:-C
#	$scoreSum = expNormalizeArray($NORMALIZE_EXP_COEFF, \@oldFreqDistro, \@freqDistro);

	$scoreSum = sum( 0, values %selPostings, values %perfectPostings );
	
	if($scoreSum == 0){
		if($DEBUG & DBG_MATCH_TITLE){
			print $LOG "Zero match\n";
		}
		return ( [], [] );
	}
	
	# Only merge imperfect postings. Perfect postings are kept. Otherwise a perfect posting may be generalized
	# to its parent term. E.g. from "Data structures" to "Algorithms and data structures"
	# its IC reduces unnecessarily
	my %mergeMap = mergeNearbyTerms($ancestorTree, \%selPostings, 2);
	my %mergedFreq;

	while(($posting, $score) = each %selPostings){
		my $mappedPosting = $mergeMap{$posting}->[0];	# merge depth ($mergeMap{$posting}->[1]) is not used here
		$mergedFreq{$mappedPosting} += $score;
#		push @{ $origPostings{$mappedPosting} }, $posting;
#		push @{ $origFreqs{$mappedPosting} },    $score;

		if($DEBUG & DBG_MATCH_TITLE){
			if($mappedPosting != $posting){
				print $LOG "$terms[$posting]($posting) => $terms[$mappedPosting]($mappedPosting), $score\n";
			}
			else{
				print $LOG "$terms[$posting]($posting), $score\n";
			}
		}
	}

	while(($posting, $score) = each %perfectPostings){
		$mergedFreq{$posting} += $score;
	}
	
=pod
	@freqDistro = values %mergedFreq;

	my $entropy = entropy(@freqDistro);
	my $scale = $scoreSum / ($entropy + 1);

	($entropy, $scale) = trunc(4, $entropy, $scale);

	if($DEBUG & DBG_MATCH_TITLE){
		print $LOG "scoreSum: $scoreSum, entropy+1: ", $entropy + 1, ", scale: $scale\n";
	}

	# each hash value of %origFreqs is an array, so the name is "orig"-"Freqs"
	# for %mergedFreq, each value is a number, so the name is "merged"-"Freq"
	
	for $posting(keys %origFreqs){
		map { $_ = trunc(4, $_ * $scale); } @{ $origFreqs{$posting} };
	}
	
	map { $_ = trunc(4, $_ * $scale); } values %mergedFreq;
=cut
	
	my @sortedPostings = sort { $mergedFreq{$b} <=> $mergedFreq{$a} } keys %mergedFreq;

	for $posting(@sortedPostings){
		last if $mergedFreq{$posting} < $MATCH_LEAST_FREQ_AFTER_ENTROPY_DISCOUNT;

		if($MERGE_NEARBY_TERMS_IN_MATCH_RESULT){
			push @postingSet, $posting;
			push @freqDeltaSet, $mergedFreq{$posting};
		}
		else{
			push @postingSet, @{ $origPostings{$posting} };
			push @freqDeltaSet, @{ $origFreqs{$posting} };
		}
	}

	# if no significant match, this match is quite suspicious 
	# (unimportant keywords that appear in many terms?). give it a discount
	if( 0 == grep { $_ >= $SIGNIFICANT_MATCH_LEAST_SCORE } @freqDeltaSet ){
		map { $_ *= $ALL_BAD_MATCHES_DISCOUNT } @freqDeltaSet;
	}
	
	if($DEBUG & DBG_MATCH_TITLE){
		my $freqDeltaSum = sum(@freqDeltaSet) || 0;
		print $LOG scalar @postingSet, " terms' freqs will be added with $freqDeltaSum\n";
	}

	return ( \@postingSet, \@freqDeltaSet );
}

sub matchTitle($$$$$)
{
	my ($ancestorTree, $titleNo, $title, $weightThres, $isTraining) = @_;

	if($DEBUG & DBG_MATCH_TITLE){
		print $LOG ">>$titleNo $title\n";
	}

	my (@lemmaIDs, @stopwordGapNums, @stopwordGapWeights, @words);
	extractTitleTokens( $title, \@lemmaIDs, \@stopwordGapNums, \@stopwordGapWeights );
	@words = map { $lemmaCache[$_]->[0] } @lemmaIDs;

	my %maxMatchScores;
	my %accumuMatchScores;

	my (@postingSets, @maxsets, @gapDiscounts, @matchWeights);
	my (@winsPostings, @winsMaxsets, @winsGapDiscounts);

	my ($i, $j);

	for($i = $j = 0; $j < @words;){
		matchPhrase( [ @words[$i .. $j] ], [ @lemmaIDs[$i .. $j] ], [ @stopwordGapNums[$i .. $j] ], 
						[ @stopwordGapWeights[$i .. $j] ], \@postingSets, \@maxsets, \@gapDiscounts );

		push @winsPostings, [ @postingSets ];
		push @winsMaxsets, [ @maxsets ];
		push @winsGapDiscounts, [ @gapDiscounts ];
		
		# the window is at full size now. So the left side of the window needs also move right
		if($j >= $MATCH_TERM_WINDOW - 1){
			$i++;
		}
		$j++;
	}

	my @impliedSubsets;
	my %impliedSubsets;
	my $maxset;
	my @winTokenIndices;

	my $lastWindowSize = min($MATCH_TERM_WINDOW, scalar @words);
	my $winMask = (1 << $lastWindowSize) - 1;	# 0b11111

	my @winLemmaIDs;
	my $qWinWords;
	my ($pTermIDs, $pFreqs, $pMatchWeights, $perfectMatchTermID);
	my $matchingTermCount;
	my @postings;
	my @freqDeltaSets;
	my @maxfreqs;
	my %perfectSieve;

	my $maxStopwordGapWeight;
	my @missedHyphenTokenIDs;
	my ($iq, $gapDiscount);
	
	for($j = @words - 1; $j >= 0; $j--){
		@postingSets = @{$winsPostings[$j]};
		@maxsets  = @{$winsMaxsets[$j]};
		@gapDiscounts = @{$winsGapDiscounts[$j]};
		
		$i = $j - $MATCH_TERM_WINDOW + 1;
		if($i < 0){
			$i = 0;
		}

		# only consider matches to elements in maxsets
		for($iq = 0; $iq < @maxsets; $iq++){
			$maxset = $maxsets[$iq];
			$gapDiscount = trunc( 2, $gapDiscounts[$iq] );
			
			@winTokenIndices = bitmap2nums($MATCH_TERM_WINDOW, $maxset);
			my @tokenIndices = map { $_ + $i } @winTokenIndices;
			@winLemmaIDs = map { $lemmaIDs[ $_ ] } @tokenIndices;
			my @qWinWords;
			my $qi;
			# @winLemmaIDs has the same length as @tokenIndices
			for( $qi = 0; $qi < @tokenIndices - 1; $qi++ ){
				push @qWinWords, $lemmaCache[ $winLemmaIDs[$qi] ]->[0];
				my $gap = $tokenIndices[ $qi + 1 ] - $tokenIndices[$qi];
				# Put '_' in place of gaps between terms of the query. One '_' for one missing word
				push @qWinWords, ('_') x $gap;
			}
			push @qWinWords, $lemmaCache[ $winLemmaIDs[$qi] ]->[0];
			$qWinWords = quoteArray( @qWinWords );
			
			# the matching scores depend on $gapDiscount. So when putting/getting it to/from the cache
			# We need specify $gapDiscount. Otherwise two queries with diff $gapDiscount and same lemmas
			# would be given the same set of matching scores
			my $matchset_uuid = join(",", @winLemmaIDs, $gapDiscount);

			if(@tokenIndices > 1){
				$maxStopwordGapWeight = max( map { $stopwordGapWeights[$_] } @tokenIndices[ 1 .. $#tokenIndices ] );
				
				if($maxStopwordGapWeight > $MAX_STOPWORD_GAP_WEIGHT_IN_QUERY){
					if($DEBUG & DBG_MATCH_TITLE){
						print $LOG "SKIPPED: $qWinWords. Max stopword gap weight $maxStopwordGapWeight > $MAX_STOPWORD_GAP_WEIGHT_IN_QUERY\n";
					}
					next;
				}
				if( checkHyphenedTokens(\@tokenIndices, \@stopwordGapNums, \@missedHyphenTokenIDs) ){
					if($DEBUG & DBG_MATCH_TITLE){
						print $LOG "SKIPPED: $qWinWords. Hyphened word(s) ", 
									quoteArray( tokenIDs2words(\@lemmaIDs, \@missedHyphenTokenIDs) ), 
									" is/are missing\n";
					}
					next;
				}
			}
						
			if(! $impliedSubsets{$maxset} ){
				if(@winLemmaIDs == 1){
					my $singleLemma = getLemma($winLemmaIDs[0]);
					
#					if($DISABLE_1_TOKEN_QUERY_PARTIAL_MATCH && $singleLemma =~ /[^A-Z]/ ){
#						next;
#					}

					if($reliantLemmas{$singleLemma}){
						if($DEBUG & DBG_MATCH_TITLE){
							print $LOG "RELIANT: $singleLemma\n";
						}
						next;
					}
				}

				if($DEBUG & DBG_MATCH_TITLE){
					print $LOG "MAXIMAL: $qWinWords\n";
				}	

				@postings = grep { $visited[$_] } @{ $postingSets[$maxset] };
				$matchingTermCount = @postings;

				# no matching term is visited (during the concept net traversal). ignore this maxset
				if( $matchingTermCount == 0){
					next;
				}

				if( $matchingTermCount > $TOKEN_MAX_MATCH_TERMS ){
					if($DEBUG & DBG_MATCH_TITLE){
						print $LOG "$matchingTermCount matching terms, ignore\n";
					}

					# subsets of this set is needless to consider (they have more matching terms)
					push @impliedSubsets, $maxset;
					next;
				}

# 03/22/2012 USE $gapDiscount INSTEAD
# calculation of $skipQueryTokenDiscount is only for comparison with $gapDiscount. Not applied anymore
				# for the matched words in the query, how many tokens are skipped between them
				my $skipQueryTokenNum = calcSkipNum(\@winTokenIndices);
				my $skipQueryTokenDiscount = $SKIP_QUERY_TOKEN_DISCOUNT ** $skipQueryTokenNum;

				if($DEBUG & DBG_MATCH_TITLE){
					print $LOG "Skipped query tokens: $skipQueryTokenNum, discount: $skipQueryTokenDiscount. gapDiscount: $gapDiscount\n";
				}

				($pTermIDs, $pFreqs, $pMatchWeights) = (undef) x 3;

				if(exists $matchSetCache{$matchset_uuid}){
					($pTermIDs, $pFreqs, $perfectMatchTermID) = @{ $matchSetCache{$matchset_uuid} };
				}

				# exists in cache
				if($pTermIDs && $pFreqs){
					# skip empty results
					if(@$pTermIDs){
						push @freqDeltaSets, [ \@tokenIndices, $qWinWords, $pTermIDs, $pFreqs, $perfectMatchTermID ];

						if($perfectMatchTermID > 0){
							for(@tokenIndices){
								$perfectSieve{$_} = $perfectMatchTermID;
							}
							if($DEBUG & DBG_MATCH_TITLE){
								print $LOG "PERFECT MATCH: $perfectMatchTermID, '$terms[$perfectMatchTermID]'\n";
							}
						}
					}
					#addFreqs($ancestorTree, $pTermIDs, $pFreqs);
					$matchSetCacheHitCount++;
				}
				else{
					@matchWeights = map { calcMatchScore($_, \@winLemmaIDs, \@winTokenIndices) }
												@postings;

					if($gapDiscount < 1){
						@matchWeights = map { $_ * $gapDiscount } @matchWeights;
					}

					$perfectMatchTermID = first_index { $_ == 1 } @matchWeights;
					if( $perfectMatchTermID >= 0 ){
						$perfectMatchTermID = $postings[ $perfectMatchTermID ];
					}

					($pTermIDs, $pFreqs) = distributeMatches($ancestorTree, \@postings,
												\@matchWeights, $maxset, $weightThres);
					if($CACHE_MATCH_SET && $matchingTermCount > $MATCH_SET_SIZE_CACHE_THRES){
						$matchSetCache{$matchset_uuid} = [ $pTermIDs, $pFreqs, $perfectMatchTermID ];
					}
					if(@$pTermIDs){
						push @freqDeltaSets, [ \@tokenIndices, $qWinWords, $pTermIDs, $pFreqs, $perfectMatchTermID ];

						if($perfectMatchTermID > 0){
							for(@tokenIndices){
								$perfectSieve{$_} = $perfectMatchTermID;
							}
							if($DEBUG & DBG_MATCH_TITLE){
								print $LOG "PERFECT MATCH: $perfectMatchTermID, $terms[$perfectMatchTermID]\n";
							}
						}
					}
					#addFreqs($ancestorTree, $pTermIDs, $pFreqs);
				}
#				else{
#					if($pTermIDs && $pFreqs){
#						recordBestMatches(\%maxMatchScores, $pTermIDs, $pFreqs, $maxset, $i);
#					}
#					else{
#						@matchWeights = map { calcMatchScore($_, \@winLemmaIDs, \@winTokenIndices) }
#													@postings;
#
#						if($skipQueryTokenDiscount < 1){
#							@matchWeights = map { $_ * $skipQueryTokenDiscount } @matchWeights;
#						}
#
#						($pTermIDs, $pFreqs) = distributeMatches($ancestorTree, \@postings,
#													\@matchWeights, $maxset);
#						recordBestMatches(\%maxMatchScores, $pTermIDs, $pFreqs, $maxset, $i);
#						if($CACHE_MATCH_SET && $matchingTermCount > $MATCH_SET_SIZE_CACHE_THRES){
#							$matchSetCache{$matchset_uuid} = [ $pTermIDs, $pFreqs ];
#						}
#					}
#				}
				push @impliedSubsets, $maxset;
			}
			else{
				if($DEBUG & DBG_MATCH_TITLE){
					print $LOG "COVERED: $qWinWords\n";
				}
			}
		}	# for $maxset(@maxsets){
		if($j >= $MATCH_TERM_WINDOW){
			for(@impliedSubsets){
				$_ = ($_ << 1) & $winMask;
			}
		}
		else{
			# initial smaller size windows. mask is also smaller, and no shift of bits
			$winMask >>= 1;
			for(@impliedSubsets){
				$_ = $_ & $winMask;
			}
		}

		%impliedSubsets = map { $_ => 1 } @impliedSubsets;
	} # for($j = @words - 1; $j >= 0; $j--){

	my $freqDeltaSet;
	my $coverTermID;
	my $isCovered;
	my $tokenIndices;

	for $freqDeltaSet(@freqDeltaSets){
		( $tokenIndices, $qWinWords, $pTermIDs, $pFreqs, $perfectMatchTermID ) = @$freqDeltaSet;
		if($perfectMatchTermID > 0){
			$isCovered = 0;
		}
		else{
			$coverTermID = first { $perfectSieve{$_} } @$tokenIndices;
			if( defined($coverTermID) ){
				$coverTermID = $perfectSieve{$coverTermID};
			}
			if($coverTermID && max(@$pFreqs) <= $MAX_WEIGHT_COV_BY_PERFECT_MATCH){
				$isCovered = 1;
			}
			else{
				$isCovered = 0;
			}
		}
		if(! $isCovered){
			if($DEBUG & DBG_MATCH_TITLE){
				print $LOG "ADD: $qWinWords\n";
			}
			if($isTraining){
				addMatchScores(\%accumuMatchScores, $pTermIDs, $pFreqs);
			}
			else{
				recordBestMatches(\%maxMatchScores, $pTermIDs, $pFreqs, $tokenIndices);
			}
		}
		else{
			if($DEBUG & DBG_MATCH_TITLE){
				print $LOG "COVERED BY PERFECT MATCH ($coverTermID, $terms[$coverTermID]): $qWinWords\n";
			}
		}
	}

	if($DEBUG & DBG_MATCH_TITLE){
		print $LOG "<<$titleNo $title\n";
	}

	if($isTraining){
		return %accumuMatchScores;
	}
	return %maxMatchScores;
}

sub calcMatchScore
{
	my ($termID, $qLemmaIDs, $tokenIndices) = @_;

#	if($ICs[$termID] < 0){
#		return -1;
#	}

	if($DEBUG & DBG_CALC_MATCH_WEIGHT){
		print $LOG "$termID '$terms[$termID]': ";
	}

	my %querywords;
	# suffix doesn't always mean the suffix of a word. it could also be "STOPWORD"
	my ($token, $lemma, $suffix);
	my $i;
	# @tokens are the tokens of the term being matched to
	my @tokens = @{ $termTokens[$termID] };
	my $T = @tokens;
	my $W = @$qLemmaIDs;
	my $W2 = 0;

	my ($qwLemma, $qwSuffix);
	
	my $suffixDiscount = 1;
	
	my $suffixMatchScore;

	my $singleTokenScore;

	my $termHasContext = $T > $termContextStart[$termID];
	
	if($W == 1){
		($qwLemma, $qwSuffix) = @{ $lemmaCache[ $qLemmaIDs->[0] ] };
		# the first lemma in the checked term
		($lemma, $suffix)     = @{ $lemmaCache[ $tokens[0] ] };

		# no partial match for 1-token query 
		# a term with context matching in the main is not considered a partial match, but it can only
		# match a query of all capitals
		# a term without context can match a query without constraint
		if($termContextStart[$termID] > 1 && $DISABLE_1_TOKEN_QUERY_PARTIAL_MATCH){
			if($DEBUG & DBG_CALC_MATCH_WEIGHT){
				print $LOG "single lemma matches a term who has a multi-lemma main. ignore\n";
			}
			return 0;
		}
		if($termContextStart[$termID] == 1){
			# if $T > 1, and context start == 1, it means this term has context
			# 'environment' won't match 'environment (blah blah)'. 'MDL' will match 'MDL (...)'
			# 'workflow' can match 'workflows' ( $T == 1, no context )
			# 'check' won't match 'Check in (Revision control)' 
			# After removing stop words, 'Check in' becomes 'Check'
			
			# TFIAF has to >= 1. to block common and less evidential words
			my $singleLemmaTFIAF;
			
			if( $qwSuffix == STOPWORD ){
				$singleLemmaTFIAF = 0;
			}
			elsif( ! exists $gUnigrams{$qwLemma} ){
				# a word absent in unigram.csv. Probably a rare word. So consider it
				# assign it an arbitrary number bigger than $MIN_VALID_1_QUERY_TOKEN_TFIAF
				$singleLemmaTFIAF = $MIN_VALID_1_QUERY_TOKEN_TFIAF + 1;
			}
			else{
				$singleLemmaTFIAF = $gUnigrams{$qwLemma}->tfiaf;
			}
			if( $T > 1 && $qwLemma =~ /[a-z]/ && $singleLemmaTFIAF < $MIN_VALID_1_QUERY_TOKEN_TFIAF ){
				if($DEBUG & DBG_CALC_MATCH_WEIGHT){
					print $LOG "Single lemma '$qwLemma' is not in all capitals, TFIAF $singleLemmaTFIAF, and matches a term with context. Ignore\n";
				}
				return 0;
			}
			
			# q: 'compression' vs 'volume (compression)'. 
			# the previous check actually will already exclude it, as it's lowercase & tfiaf < 1
			# another coined example: 'MDL' vs 'minimum description length (MDL)'
			if($lemma ne $qwLemma){
				if($DEBUG & DBG_CALC_MATCH_WEIGHT){
					print $LOG "Single lemma matches only in context. Ignore\n";
				}
				return 0;
			}
			
			if($suffix == $qwSuffix){
				$suffixMatchScore = 1;
			}
			# 'thresholding' vs 'threshold'
			# no match between two single-token terms of different suffices
			elsif($DISABLE_1_TOKEN_DIFF_SUFFIX_MATCH){
				if($DEBUG & DBG_CALC_MATCH_WEIGHT){
					print $LOG "Single lemma matches a term who has a single-lemma main, but diff suffix. ignore\n";
				}
				return 0;
			}
			else{
				$suffixMatchScore = $DIFF_SUFFIX_DISCOUNT;
				$suffixDiscount *= $DIFF_SUFFIX_DISCOUNT;
			}
			
			$singleTokenScore = $MATCH_1_TOKEN_QUERY_DISCOUNT;
			if($termHasContext){
				$singleTokenScore *= $MATCH_1_TOKEN_QUERY_TO_TERM_WITH_CONTEXT_DISCOUNT;
			}
			
			if($DEBUG & DBG_CALC_MATCH_WEIGHT){
				print $LOG "\$singleTokenScore = $singleTokenScore. \$suffixDiscount = $suffixDiscount\n";
			}
			return $singleTokenScore * $suffixDiscount;
		}
	}
	
	for($i = 0; $i < $W; $i++){
		($token, $suffix) = @{ $lemmaCache[ $qLemmaIDs->[$i] ] };
		$querywords{$token} = $i + 1;
		if($suffix != STOPWORD){
			$W2++;
		}
	}

	my $matchWeight = 0;
	my $missWeight = 0;
	my $knownTokenCount = 0;
	my $unknownTokenCount = 0;
	my $stopwordsInContext = 0;
	my $stopwordsInMain = 0;
	my $unmatchedStopwordsInContext = 0;
	my $unmatchedStopwordsInMain = 0;
	my @matchSeq;
	my $contextWC = 0;
	my $mainWC = 0;
	my %bestMatchInMain;
	my %bestMatchInContext;
	my %matchCountInMain;
	my %matchCountInContext;

	my $lemmaIdx;
	my $isInContext;
	my $contextDiscount;

	for($i = 0; $i < $T; $i++){
		$isInContext = $i >= $termContextStart[$termID];
		$contextDiscount = $isInContext ? $CONTEXT_MATCH_DISCOUNT : 1;

		($token, $suffix) = @{ $lemmaCache[ $tokens[$i] ] };

		if($suffix == STOPWORD){
			if($isInContext){
				$stopwordsInContext++;

			}
			else{
				$stopwordsInMain++;
			}
		}

		if($lemmaIdx = $querywords{$token}){
			$qwSuffix = $lemmaCache[ $qLemmaIDs->[$lemmaIdx - 1] ]->[1];

			# if a stopword is matched, it's ignored and contributes no point to the final match score
			# especially, it won't be pushed into @matchSeq, because the order
			# of a stopword is generally not important
			# but if a stopword is absent, it decreases the match score
			# such as "agent" against "the agent". with "the", the term is more specific

			next if $suffix == STOPWORD;

			if($suffix == $qwSuffix){
				$suffixMatchScore = 1;
			}
			else{
				$suffixMatchScore = $DIFF_SUFFIX_DISCOUNT;
				$suffixDiscount *= $DIFF_SUFFIX_DISCOUNT;
			}

			# if a token both appears in main and the context, choose the occurrence in
			# the main only.
			if(! $isInContext){
				push @matchSeq, $querywords{$token};

				$matchCountInMain{$token}++;
				if($matchCountInMain{$token} == 1){
					$mainWC++;
					$bestMatchInMain{$token} = $suffixMatchScore;
				}
				else{
					if($suffixMatchScore > $bestMatchInMain{$token}){
						$bestMatchInMain{$token} = $suffixMatchScore;
					}
				}
			}
			else{
				# $token hasn't appeared in main, and now $token appears in context. so count it in
				if(! $matchCountInMain{$token}){
					push @matchSeq, $querywords{$token};

					$matchCountInContext{$token}++;

					if($matchCountInContext{$token} == 1){
						$contextWC++;
						$bestMatchInContext{$token} = $suffixMatchScore;
					}
					else{
						if($suffixMatchScore > $bestMatchInContext{$token}){
							$bestMatchInContext{$token} = $suffixMatchScore;
						}
					}
				}
			}
		}
		else{
			if(exists $gUnigrams{$token}){
				$knownTokenCount += $contextDiscount;
				$missWeight += $gUnigrams{$token}->tfiaf * $contextDiscount;
			}
			else{
				if($suffix == STOPWORD){
					if($isInContext){
						$unmatchedStopwordsInContext++;
					}
					else{
						$unmatchedStopwordsInMain++;
					}
				}
				else{
					$unknownTokenCount += $contextDiscount;
				}
			}
		}
	}

	if($mainWC == 0){
		if($DEBUG & DBG_CALC_MATCH_WEIGHT){
			print $LOG "Match only on context. ignore\n";
		}
		return 0;
	}

	if( $unknownTokenCount >= 2 ){
		if($DEBUG & DBG_CALC_MATCH_WEIGHT){
			print $LOG "$unknownTokenCount term words don't appear in DBLP\n";
		}
		return 0;
	}

	my $fullWeight = $missWeight * $MATCH_MISS_TOKEN_PUNISHMENT;

	for $token(keys %bestMatchInMain){
		$knownTokenCount += 1;

		# $fullWeight and $matchWeight are increased by different amounts.
		# the difference is equivalent to adding to $missWeight the mismatch discount of a suffix
		$fullWeight  += $gUnigrams{$token}->tfiaf;
		#$matchWeight += $gUnigrams{$token}->tfiaf * $bestMatchInMain{$token};
		# punish the whole matching score later instead
		$matchWeight += $gUnigrams{$token}->tfiaf;
	}

	for $token(keys %bestMatchInContext){
		$knownTokenCount += $CONTEXT_MATCH_DISCOUNT;
		$fullWeight  += $gUnigrams{$token}->tfiaf * $CONTEXT_MATCH_DISCOUNT;
		#$matchWeight += $gUnigrams{$token}->tfiaf * $bestMatchInContext{$token} * $CONTEXT_MATCH_DISCOUNT;
		$matchWeight += $gUnigrams{$token}->tfiaf * $CONTEXT_MATCH_DISCOUNT;
	}

	if($matchWeight == 0 && $missWeight == 0){
		if($DEBUG & DBG_CALC_MATCH_WEIGHT){
			print $LOG "FATAL: have matchWeight=missWeight=0\n";
		}
		return 0;
	}

	my $unknownWeightEst = 0;
	my $unmatchedStopwordsDiscount = 1;

	if($unknownTokenCount > 0){
		# for each unknown token, we want to give it the average (full) weight
		# of all known tokens, times $MATCH_UNKNOWN_TOKEN_WEIGHT to punish for unknown tokens
		# it's roughly equivalent to giving the final match weight a discount of
		# $MATCH_UNKNOWN_TOKEN_WEIGHT/n, where n is the number of tokens of this term
		$unknownWeightEst = $MATCH_UNKNOWN_TOKEN_WEIGHT * $unknownTokenCount * $fullWeight
								/ $knownTokenCount;

		if($DEBUG & DBG_CALC_MATCH_WEIGHT){
			print $LOG "\$unknownWeightEst=", trunc(3, $unknownWeightEst), ", ";
		}
	}

	if($unmatchedStopwordsInMain > 0){
		# for each unmatched stopword in main, we want to give it a fraction of the average (full) weight
		# of all known tokens.
		# it's roughly equivalent to giving the final match weight a discount of
		# $UNMATCHED_STOPWORD_DISCOUNT/n
		$unmatchedStopwordsDiscount = $UNMATCHED_STOPWORD_DISCOUNT ** $unmatchedStopwordsInMain;

		if($DEBUG & DBG_CALC_MATCH_WEIGHT){
			print $LOG "\$unmatchedStopwordsDiscount=",
							trunc(3, $unmatchedStopwordsDiscount), ", ";
		}
	}

	if($suffixDiscount < 1 && $DEBUG & DBG_CALC_MATCH_WEIGHT){
		print $LOG "\$suffixDiscount=", trunc(3, $suffixDiscount), ", ";
	}
		
	my $matchWeightFrac = $suffixDiscount * $unmatchedStopwordsDiscount * $matchWeight
								/ ($fullWeight + $unknownWeightEst);

	if( $mainWC == 1 && $termContextStart[$termID] > $mainWC + $stopwordsInMain ){
		# $W2 is the count of non-stopwords in the QUERY
		if($W2 > 1){
			if($DEBUG & DBG_CALC_MATCH_WEIGHT){
				print $LOG "\$matchWeightFrac = ", trunc(4, $matchWeightFrac),
							", only 1 token matched in main ~ 0\n";
			}
			return 0;
		}
		else{
			# consider the case when the other token(s) is(are) known. otherwise,
			# $MATCH_UNKNOWN_TOKEN_WEIGHT already punishes for the unknown (and unmatched) token(s)
			if($unknownTokenCount == 0){
				$matchWeightFrac *= $MATCH_1_OF_N_TOKENS_DISCOUNT;
			}
		}
	}

	# only 1 word is both in the query and in the main of the term. but the suffix is different
	# Give the total match value a discount of $DIFF_SUFFIX_1_TOKEN_DISCOUNT
	if( $W == 1 && $termContextStart[$termID] == 1 ){
		my $termToken1Suffix  = $lemmaCache[ $tokens[0] ]->[1];
		my $queryToken1Suffix = $lemmaCache[ $qLemmaIDs->[0] ]->[1];
		if($termToken1Suffix != $queryToken1Suffix){
			$matchWeightFrac *= $DIFF_SUFFIX_1_TOKEN_DISCOUNT;
		}
	}

	if( $mainWC == 1 && $contextWC == 0 && $termHasContext && $termContextStart[$termID] > 1){
		$matchWeightFrac *= $MATCH_1_MISS_CONTEXT_DISCOUNT;
	}

#	if($matchWeightFrac < $MATCH_LEAST_WEIGHT){
#		if($DEBUG & DBG_CALC_MATCH_WEIGHT){
#			print $LOG "\$matchWeightFrac = ", trunc(3, $matchWeightFrac), " ~ 0\n";
#		}
#		return 0;
#	}

	my $invNum = calcMisalignment($W, \@matchSeq);
	if($invNum > 0){
		if($DEBUG & DBG_CALC_MATCH_WEIGHT){
			print $LOG "\$invNum = $invNum, ";
		}

		$matchWeightFrac *= $INVERSION_DISCOUNT ** $invNum;
#		if($matchWeightFrac < $MATCH_LEAST_WEIGHT){
#			if($DEBUG & DBG_CALC_MATCH_WEIGHT){
#				print $LOG "\$matchWeightFrac = ", trunc(3, $matchWeightFrac), " ~ 0\n";
#			}
#			return 0;
#		}
	}

	$matchWeightFrac = trunc(4, $matchWeightFrac);

	if($DEBUG & DBG_CALC_MATCH_WEIGHT){
		print $LOG "\$matchWeightFrac = $matchWeightFrac\n";
	}

	return $matchWeightFrac;
}

sub calcSkipNum
{
	my @nums = grep { defined($_) } @{$_[0]};
	my $skipnum = 0;

	my $i;
	for($i = 1; $i < @nums; $i++){
		if($nums[$i] > $nums[$i - 1] + 1){
			$skipnum += $nums[$i] - $nums[$i - 1] - 1;
		}
	}
	return $skipnum;
}
	
sub calcInvNum0
{
	my $W = $_[0];
	my @nums = grep { defined($_) } @{$_[1]};

	die if $W != @nums;

	my ($i, $j);

	my $invNum = 0;

	for($i = 1; $i < $W; $i++){
		for($j = 0; $j < $i; $j++){
			if($nums[$i] < $nums[$j]){
				$invNum++;
			}
		}
	}

	return $invNum;
}

sub calcMisalignment
{
	my $W = $_[0];
	return 0 if $W == 1;

	my $N = @{$_[1]};

	# no duplicates
	if($W == $N){
		return calcInvNum0(@_);
	}

	my @nums = @{$_[1]};

	my ($onepos, $wpos);
	my $i;

	# we can easily find the optimal pos for 1 and $W
	for($i = 0; $i < $N; $i++){
		if($nums[$i] == 1){
			$onepos = $i;
			last;
		}
	}
	for($i = $N - 1; $i >= 0; $i--){
		if($nums[$i] == $W){
			$wpos = $i;
			last;
		}
	}

	if($W == 2){
		return $onepos > $wpos;
	}

	my @freqTable;
	my @invTable;
	my $num;

	for($i = 0; $i < $N; $i++){
		$num = $nums[$i];

		if(!$invTable[$num]){
			$invTable[$num] = [ $i ];
		}
		else{
			push @{ $invTable[$num] }, $i;
		}
		$freqTable[ $num ]++;
	}

	# represent each position of a word as a digit in a number
	# $carry stores the index of the carry. if $carry == $W, this number overflows
	# it means all possible combinations are enumerated, so we stop

	my @digits   = (0) x $W;
	my $carry;

	my @seq;
	my @invnums;
	my @skipnums;

	do{
		@seq = ();
		$seq[$onepos] = 1;
		$seq[$wpos]   = $W;

		$carry = 2;
		for($i = 2; $i < $W; $i++){
			$seq[ $invTable[$i]->[$digits[$i]] ] = $i;

			if($i == $carry){
				if($digits[$i] < $freqTable[$i] - 1){
					$digits[$i]++;
				}
				else{
					$digits[$i] = 0;
					$carry++;
				}
			}
		}
		push @invnums,  calcInvNum0($W, \@seq);
		push @skipnums, calcSkipNum(\@seq);

	}while($carry < $W);

	my $minMisalign = 1000;
	my $minIndex = -1;
	for($i = 0; $i < @invnums; $i++){
		if($skipnums[$i] * $SKIP_TOKEN_EQ_INVERSION + $invnums[$i] < $minMisalign){
			$minMisalign = $skipnums[$i] * $SKIP_TOKEN_EQ_INVERSION + $invnums[$i];
			$minIndex = $i;
		}
	}

	return $minMisalign;
}

sub checkHyphenedTokens
{
	my ($pTokenIndices, $pStopwordGapNums, $pMissedHyphenTokenIDs) = @_;
	
	@$pMissedHyphenTokenIDs = ();
	
	my $i;
	my $index;
	
	for($i = 0; $i < @$pTokenIndices; $i++){
		$index = $pTokenIndices->[ $i ];
		
		# a left-hyphened word must be consectutive to the word before it
		if($pStopwordGapNums->[$index] == -1 && 
				( $i == 0 || $index - 1 != $pTokenIndices->[ $i - 1 ] ) ){
			push @$pMissedHyphenTokenIDs, $index - 1;
		}
		# a right-hyphened word must be consectutive to the word after it
		elsif($pStopwordGapNums->[$index + 1] == -1 &&
				( $i == @$pTokenIndices - 1 || $index + 1 != $pTokenIndices->[ $i + 1 ] ) ){
			push @$pMissedHyphenTokenIDs, $index + 1;
		}
	}
	
	return scalar @$pMissedHyphenTokenIDs;
}

sub unigramMatchTitle($$)
{
	my ( $titleNo, $title ) = @_;

	if($DEBUG & DBG_MATCH_TITLE){
		print $LOG ">>$titleNo $title\n";
	}

	my (@lemmaIDs, @stopwordGapNums, @stopwordGapWeights, @words);
	extractTitleTokens($title, \@lemmaIDs, \@stopwordGapNums, \@stopwordGapWeights);
	@words = map { $lemmaCache[$_]->[0] } @lemmaIDs;

	my %matches;
	
	my $i;
	my $lemmaID;
	for($i = 0; $i < @lemmaIDs; $i++){
		$lemmaID = $lemmaIDs[$i];
		
		# keep compatible with the concept vector: [ weight, [ token_indices ] ]
		$matches{$lemmaID} = [ 1, [ $i ] ];
	}

	if($DEBUG & DBG_MATCH_TITLE){
		print $LOG join( ",", @words ), "\n";
		print $LOG "<<$titleNo $title\n";
	}

	return %matches;
}

sub calcNetIC
{
	my %args = @_;

	print $tee "Calculating the ICs of the network:\n";

	if($MC == 0){
		print $tee "No match to terms, the freqs are all zero. Abort\n";
		return;
	}
	if($freqs[0] != $MC){
		print $tee "INCONSISTENCY: MC $MC != root freq $freqs[0], should never happen\n";
		$MC = $freqs[0];
	}

	my $i;

	my $logMC = log($MC);

	for($i = 0; $i < $termGID; $i++){
		if(!$freqs[$i]){
			$ICs[$i] = -1;
		}
		else{
			if($i > 0 && !$bfsDepth[$i]){
				if($DEBUG & DBG_CALC_IC){
					print $LOG "Term $i '$terms[$i]' not visited by bfs, but has freq $freqs[$i]\n";
				}
				$ICs[$i] = -1;
			}
			else{
				$ICs[$i] = trunc( 4, $logMC - log($freqs[$i]) );
			}
		}
	}

	print $tee "$termGID terms calculated. MC=$MC\n";

	$lastCalcMC = $MC;
}

sub saveNetIC
{
	my %args = @_;
	my $filename = $args{filename};

	$filename = getAvailName($filename);

	print $tee "Saving network ICs into '$filename'...\n";

	if($MC == 0){
		print $tee "There hasn't been any match. No need to save IC (will be all -1). Abort\n";
		return;
	}
	if($MC != $lastCalcMC ){
		print $tee "Last calculated MC is $lastCalcMC, but now MC is $MC. Update ICs first.\n";
		calcNetIC(%args);
	}

	my $IC;
	open_or_die($IC, "> $filename");

	my $i;

	print $tee "Sorting \@ICs descendingly...";

	my @sortedIDs = sort { $ICs[$b] <=> $ICs[$a] } (0 .. $termGID - 1);

	print $tee " Done.\n";

	print $IC "# MC: $MC. addedFreqSum: $addedFreqSum. addedCountableFreqCount: $addedCountableFreqCount. authorGID: $authorGID\n";

	my $ICCount = 0;

	for $i(@sortedIDs){
		last if !$freqs[$i]; # unmatched in any title
		$gen1freqs[$i] ||= 0;
		
		print $IC "$i ", join( "\t", $terms[$i], $ICs[$i], $freqs[$i], $gen1freqs[$i], 
							scalar keys %{ $term2authorIDs[$i] } ), "\n";
		$ICCount++;
	}

	print $tee "$ICCount entries saved. MC: $MC\n";
}

sub loadNetIC
{
	my %args = @_;
	my $filename = $args{filename};

	print $tee "Loading network ICs from '$filename'...\n";

	my $IC;
	if(!open_or_warn($IC, "< $filename")){
		return;
	}

	@ICs = ();
	@freqs = ();
	@termAuthorCount = ();
	
	my $i;

	my $line = <$IC>;
	if($line =~ /# MC: ([\d.]+)\. addedFreqSum: ([\d.]+)\. addedCountableFreqCount: ([\d.]+). authorGID: ([\d]+)/){
		$MC = $1;
		$addedFreqSum = $2;
		$addedCountableFreqCount = $3;
		$authorGID = $4;
		print $tee "$line";
		$avgMatchScore = $addedFreqSum / $addedCountableFreqCount;
		print $tee "Average match score: $avgMatchScore\n";
	}
	else{
		print $tee "WARN: Unknown IC header format, ignore:\n$line";
		$MC = 0;
	}

	my ($id_term, $ic, $freq, $gen1freq, $authorCount);
	my ($id, $term);
	
	my $termID;
	my $tc = 0;

	while($line = <$IC>){
		next if $line =~ /^#/;
		trim($line);
		next if !$line;

		($id_term, $ic, $freq, $gen1freq, $authorCount) = split /\t/, $line;
		($id, $term) = split / /, $id_term, 2;
		$termID = getTermID($term);
		if($termID < 0){
			if($DEBUG & DBG_LOAD_IC){
				print $LOG "Unknown term: '$term'\n";
			}
			next;
		}
		$ICs[$termID] = trunc(4, $ic);
		$freqs[$termID] = trunc(2, $freq);
		$gen1freqs[$termID] = trunc(2, $gen1freq);
		$termAuthorCount[$termID] = $authorCount;
		
		$tc++;
	}

	print $tee "$. line read, $tc entries loaded. MC: $MC\n";
}

sub checkAbnormalFreq
{
	my $proportion = shift || 0.99;
	my $outFilename = shift;

	print $tee "Sorting \@freqs descendingly...";

	my @sortedIDs = sort { $freqs[$b] <=> $freqs[$a] } grep { defined($freqs[$_]) } (0 .. $termGID - 1);

	print $tee " Done.\n";

	print $tee "MC: $MC\n";

	my $ICCount = 0;
	my %childrenFreq;
	my $maxfreq;
	my $freqsum;
	my $maxchildID;
	my $abnormalCount = 0;

	my $i;
	my $OUT;
	my $tee;

	if($outFilename){
		$outFilename = getAvailName($outFilename);

		open_or_die($OUT, "> $outFilename");
	}
	else{
		$OUT = \*STDERR;
	}

	for $i(@sortedIDs){
		last if $freqs[$i] < 1000;

		next if @{ $conceptNet[$i] } == 1;

		%childrenFreq = map { $_ => $freqs[$_] } grep { defined($freqs[$_]) } @{ $conceptNet[$i] };
		next if keys %childrenFreq == 0;

		$maxfreq = max(values %childrenFreq);
		$freqsum = sum(values %childrenFreq);
		if($freqsum * $proportion <= $maxfreq){
			($maxchildID) = grep { $childrenFreq{$_} == $maxfreq } keys %childrenFreq;
			print $OUT "Abnormality: $i '$terms[$i]' freqsum $freqsum, dominated by $maxchildID '$terms[$maxchildID]'\n";
			$abnormalCount++;
		}
	}

	print $OUT "$abnormalCount abnormal terms found\n";
}

sub saveAncestors
{
	my ($ancestorTree, $filename) = @_;

	$filename = getAvailName($filename);

	print $tee "Saving the ancestor list of each term into '$filename'...\n";

	my $ANCESTOR;
	if(!open_or_warn($ANCESTOR, "> $filename")){
		return;
	}

	my $i;
	my $ancestorList;
	my @ancestors;
	my $depth;
	my $batch;
	my $id;

	my $totalAncestorCount = 0;
	my $ancestorListCount = 0;

	my $progresser = makeProgresser(vars => [ \$ancestorListCount, \$totalAncestorCount ]);

	for($i = 1; $i < $termGID; $i++){
		next if !$visited[$i];

		print $ANCESTOR "$i,$terms[$i]";

		print $ANCESTOR "\t", join( ",", @{ $depthByBatch[$i] } );

		$ancestorList = $ancestorTree->[$i];
		@ancestors = sort { $ancestorList->{$a} <=> $ancestorList->{$b} } keys %$ancestorList;

		for $id(@ancestors){
			($depth, $batch) = WWSplit( $ancestorList->{$id} );
			print $ANCESTOR "\t$depth,$batch,$id,$terms[$id]";
			$totalAncestorCount++;
		}
		print $ANCESTOR "\n";
		$ancestorListCount++;
		&$progresser();
	}

	print $tee "$totalAncestorCount ancestors of $ancestorListCount terms are saved\n";
}

sub loadAncestors
{
	my ($tree, $rootterms, $ancestorTree, $inheritCount, $filename) = @_;

	my $ANCESTOR;
	if(!open_or_warn($ANCESTOR, "< $filename")){
		return;
	}

	my @roots = terms2IDs($rootterms);

	setTopAncestors($tree, \@roots);
	@$ancestorTree = ( { 0 => 0 } );
	@$inheritCount = ();

	breadthFirst( tree => $tree, roots => \@roots, bfsDepth => \@bfsDepth,
					callback => \&NO_OP);

	my $i;

	my ($mainID, $mainID2, $mainterm, $id, $id2, $depth, $batch, $term);
	my $depthList;
	# depths by batch for the current term. to avoid name collision, name it as @depth
	my @depths;
	my @tuples;
	my $tuple;
	my %wrongIDs;
	my %wrongBfsDepths;

	my $ancestorCount;

	my $totalAncestorCount = 0;
	my $ancestorListCount = 0;

	my $line;
	my $progresser = makeProgresser(vars => [ \$ancestorListCount, \$totalAncestorCount ]);

	my %errorTerms;

	print $tee "Loading ancestor lists from '$filename'...\n";

	while($line = <$ANCESTOR>){
		next if $line =~ /^#/;
		trim($line);
		next if !$line;

# 43,Dense subgraph	2,-1	0,0,43,Dense subgraph	1,0,2,computer science	2,0,0,CONCEPT_NET_ROOT
		@tuples = split /\t/, $line;
		$mainterm = shift @tuples;
		($mainID2, $mainterm) = split /,/, $mainterm, 2;

		my %ancestorList;
		$ancestorCount = 0;

		$mainID = getTermID($mainterm);
		if($mainID == -1){
			if($DEBUG & DBG_LOAD_ANCESTORS){
				print $LOG "Term '$mainterm' not found in the concept net\n";
			}
			next;
		}
		if($mainID != $mainID2){
			$wrongIDs{$mainID2} = $mainID;
		}

		# 2,-1
		$depthList = shift @tuples;
		@depths = split /,/, $depthList;
		$depthByBatch[$mainID] = [ @depths ];
		my $depth0 = $depths[0];
		# set undef for depth of -1 to capture possible bugs
		$attenuateByBatch[$mainID] = [ map { $_ > 0 ? min( 1, $depth0 / $_ ) : undef } @depths ];
		$recAttenuateByBatch[$mainID] = [ map { $_ > 0 ? max( 1, $_ / $depth0 ) : undef } @depths ];

		# set the inheritCount as the index of the last element in the $depthByBatch[$mainID]
		$inheritCount->[$mainID] = @depths;
		# set the bfsDepth as the root depth in batch 0
		if($bfsDepth[$mainID]){
			if($bfsDepth[$mainID] != $depth0){
				$wrongBfsDepths{$mainID} = $depth0;
			}
		}
		else{
			$bfsDepth[$mainID] = $depth0;
		}

		# 0,0,43,Dense subgraph	
		# 1,0,2,computer science	
		# 2,0,0,CONCEPT_NET_ROOT
		for $tuple(@tuples){
											# limit the split fields to 4. cuz $term could contain ","
			($depth, $batch, $id2, $term) = split /,/, $tuple, 4;

			if(!$term){
				print $tee "wrong tuple format: $tuple\n";
				next;
			}
			if($errorTerms{$term}){
				next;
			}
			$id = getTermID($term);
			if($id == -1){
				if($DEBUG & DBG_LOAD_ANCESTORS){
					print $LOG "Term '$term' not found in the concept net\n";
				}
				$errorTerms{$term} = 1;
				next;
			}
			if($id != $id2){
				$wrongIDs{$id2} = $id;
			}
			$ancestorTree->[$mainID]->{$id} = int( combineWW($depth, $batch) );

			$ancestorCount++;
		}

		$totalAncestorCount += $ancestorCount;
		$ancestorListCount++;
		&$progresser();
	}

	print $tee "$totalAncestorCount ancestors of $ancestorListCount terms are loaded\n";

	if($DEBUG & DBG_LOAD_ANCESTORS){
		for $id2(sort { $a <=> $b } keys %wrongIDs){
			print $LOG "IDs disagree: old $id2, new $wrongIDs{$id2}\n";
		}
		for $id(sort { $a <=> $b } keys %wrongBfsDepths){
			print $LOG "Depths disagree: file $wrongBfsDepths{$id}, existing $bfsDepth[$id]\n";
		}
	}
}

sub trainDBLPFile($$)
{
	my $dblpFilename = shift;
	my $matchWeightThres = shift;
	
	my $DBLP;
	if( !open_or_warn( $DBLP, "< $dblpFilename" ) ){
		return;
	}

	my $oldMC = $MC;

	my $thisPublication;
	my $title;
	my @authorNames;
	
	# count the total line number
	while(<$DBLP>){}
	
	my $totalRecordCount = $. / 4;
	$. = 0;
	
	if($totalRecordCount > $MAX_TRAIN_TITLE_NUM){
		$totalRecordCount = $MAX_TRAIN_TITLE_NUM;
	}
		
	seek $DBLP, 0, 0;
	
	my $startTime = time;
	my $now;
	my $estTime;
	my ( $sec, $min, $hour, $mday );
	my $estTimeStr;
	my $lineno = 0;
	
	my %termMatchScores;
	my ($termID, $score);
	
	my $refAuthorCount = 0;
	my $recordCount = 0;
	
	my $progresser = makeProgresser( vars => [ \$recordCount, \$MC, \$matchSetCacheHitCount, 
										\$postingCacheHitCount, \$refAuthorCount, \$estTimeStr ], step => 10 );

	%authorName2id = ();
	@authors = ();
	$authorGID = 0;
	
	my ( @authorIDs, $authorID );
	
	@term2authorIDs = ();
	$addedFreqSum = 0;
	$addedCountableFreqCount = 0;
	
	while(!eof($DBLP)){
		$thisPublication = parseCleanDBLP($DBLP);
		
		$recordCount++;
		
		$title = $thisPublication->title;
	#	$title = removePublisher($thisPublication->title);
		@authorNames = @{ $thisPublication->authors };
		@authorIDs = map { key2id( $_, \%authorName2id, \@authors, $authorGID ) } @authorNames;
		
		# only count in the first 3 authors. other authors have little contribution
		if(@authorIDs > 3){
			$#authorIDs = 2;
		}
		
		$lineno = $DBLP->input_line_number();
		last if $lineno >= $MAX_TRAIN_TITLE_NUM * 4;	# each record has 5 lines (4 lines + blank line)

		trim($title);
		%termMatchScores = matchTitle(\@ancestorTree, $lineno, $title, $matchWeightThres, 1);
		while( ($termID, $score) = each %termMatchScores ){
			if($score >= $LEAST_COUNTABLE_MATCH_SCORE){
				addFreqAndAuthors( \@ancestorTree, $termID, $score, \@authorIDs, \$refAuthorCount );
			}
		}
		
		if($recordCount % 10 == 0){
			$now = time;
			$estTime = ( $totalRecordCount - $recordCount ) * ( $now - $startTime ) / $recordCount;
			$estTime = int($estTime);
			$estTimeStr = "Est: " . time2hms($estTime);
		}
		&$progresser();
	}

	&$progresser(1);
	
	print $tee "$recordCount titles, ", $MC - $oldMC, " increase in match count\n";
	print $tee "$refAuthorCount authors use terms in the taxonomy\n";
	
	my $usedTime = time - $startTime;
	print $tee "Stop at: ", hhmmss(time, ":"), ". Used time: ", time2hms($usedTime), "\n";
}

# assume two keys in the hash: 'f' (from) & 't' (to)
sub updateYearRange($@)
{
	my ($h, @years) = @_;
	
	my $year;
	
	for $year(@years){
		if(!exists $h->{f} || $h->{f} > $year){
			$h->{f} = $year;
		}
		if(!exists $h->{t} || $h->{t} < $year){
			$h->{t} = $year;
		}
	}
}

sub yearRange2str($)
{
	my $h = shift;
	my $from = $h->{f} || "undef";
	my $to   = $h->{t} || "undef";
	
	if($from == $to){
		return "$from";
	}
	return "$from-$to";
}

sub calcYearRangeDiff($$)
{
	my ($h1, $h2) = @_;

	my $from1 	= $h1->{f};
	my $to1		= $h1->{t};
	my $from2 	= $h2->{f};
	my $to2		= $h2->{t};
	
	if($to1 < $from2){
		return $from2 - $to1;
	}
	if($to2 < $from1){
		return $from1 - $to2;
	}
	return 0;
}

sub calcYearDiffDiscount($)
{
	my $yearDiff = shift;
	
	if($yearDiff > $MAX_YEAR_DIFF){
		return 0;
	}
	
	$yearDiff -= $YEAR_TOLERANCE;
	if( $yearDiff <= 0 ){
		return 1;
	}
	return $YEARLY_ATTENUATE ** $yearDiff;
}

sub getTermFreqThresByAmbig($$)
{
	my ($cv, $freqSumThres) = @_;
	
	my %term2freq = map { $_ => $freqs[$_] } grep { defined( $freqs[$_] ) } keys %$cv;
	my @sortedTermsByFreq = sort { $term2freq{$a} <=> $term2freq{$b} } keys %term2freq;

	my $freqThres = 0;
	my $term;
	my $freqSum = 0;
	for $term(@sortedTermsByFreq){
		$freqSum += $term2freq{$term};
		if($freqSum > $freqSumThres){
			$freqThres = $term2freq{$term} - 1;
			last;
		}
		$freqThres = $term2freq{$term};
	}
	
	return $freqThres;
}

# $cv->{$conceptID}{tokens} are not dumped
sub dumpConceptVec($$;$)
{
	my ($FH, $cv, $useUnigram) = @_;

	my @ids = sort { $cv->{$b}{w} <=> $cv->{$a}{w} } keys %$cv;
	print $FH scalar @ids, " d.\t", join( "\t", 
		map { join( ",", $_, "'" .
				( $useUnigram ? $lemmaCache[$_]->[0] : $terms[$_] ) . "'", 
				yearRange2str( $cv->{$_} ), 
				trunc(2, $cv->{$_}->{w}), "f:" . ($freqs[$_] || 0) ) 
			} @ids ), "\n";
}

sub dumpConceptVenueVec($$;$)
{
	my ($FH, $cv_vv, $useUnigram) = @_;

	my $cv = $cv_vv->[0];
	my $vv = $cv_vv->[1];
	
	dumpConceptVec($FH, $cv, $useUnigram);
	
	print $FH scalar keys %$vv, " venues.\t", dumpSortedHash($vv, undef, undef), "\n";
}

sub dumpTitleset($$$$;$)
{
	my ($context, $clustNo, $titleset, $conceptVec, $isBriefMode) = @_;
	my $titles = $context->{titles};
	my $identities = $context->{identities};
	my $useUnigram  = $context->{useUnigram};
	
	my %idStat;
	
	print $LOG "Cluster $clustNo:\n";
	if(!$titleset || !@$titleset){
		print $LOG "Error: empty cluster. It should never happen\n";
		return;
	}

	my $titleID;
	
	my $printCount = 0;
	
	for $titleID(@$titleset){
		if( $identities->[$titleID] ){
			if( !$isBriefMode || $printCount < 5 || @$titleset == 6 ){
				print $LOG "$identities->[$titleID]. ";
			}
			$idStat{ $identities->[$titleID] }++;
		}
		if( !$isBriefMode ||  $printCount < 5 || @$titleset == 6 ){
			print $LOG "Title $titleID: $titles->[$titleID]\n";
		}
		elsif( $printCount == 5 ){
			print $LOG "...... (", scalar @$titleset - 5, " more)\n";
		}
		$printCount++;
	}
	print $LOG "Vec $clustNo: ";
	dumpConceptVenueVec($LOG, $conceptVec, $useUnigram);
	
	if(keys %idStat){
		my @ids = sort { $idStat{$b} <=> $idStat{$a} } keys %idStat;
		
		if($isBriefMode){
			print $LOG "$clustNo: ";
			print $LOG join( "   ", map { "$_: $idStat{$_}" } @ids ), "\n";
		}
		else{
			print $tee "$clustNo: ";
			print $tee join( "   ", map { "$_: $idStat{$_}" } @ids ), "\n";
		}
	}
}

sub dumpSimiTuple($$)
{
	my $tuple = shift;
	my $useUnigram = shift;
	
	my ( $maxsimi, $ICSum, $ICSumThres, $sharedVenues, $venueBoost, $sharedTermSimiSum, $sharedTerms, 
		$maxDiffTermSimi, $freqSumThres, $freqThres1, $freqThres2, $freqThres, 
		$lcs, $lcsSimi, $attenuation, $leastDepth, 
		$concept1, $w1, $concept2, $w2, $yearDiff ) = @$tuple;
	# the last var '$yearDiff' is the year diff between $concept1 & $concept2
	
	print $LOG "Combined simi: $maxsimi. IC sum: $ICSum";
	if($ICSum >= $ICSumThres){
		print $LOG " >= thres: $ICSumThres\n";
	}
	else{
		print $LOG " < thres: $ICSumThres, eliminated\n";
	}
	
	print $LOG "Freq sum thres: $freqSumThres. Single thres 1: $freqThres1. Single thres 2: $freqThres2. Choose $freqThres\n";
	print $LOG "Shared terms simi: $sharedTermSimiSum. ";
	# @$sharedTerms: [ $concept1, $sharedTermSimi, $yearDiff, $ic ]
	if( @$sharedTerms > 0 ){
		print $LOG "Shared: ";
		
		if($useUnigram){
			# $_ => [ $unigram, $sharedTermSimi, $yearDiff, $gUnigrams{$unigram}->tfiaf ]
			print $LOG join( "; ", map { join( ", ", "'$_->[0]'", $_->[1], $_->[2], "tfiaf:$_->[3]" ) } @$sharedTerms ), ".\n";
		}
		else{
			# $_ => [ $concept1, $sharedTermSimi, $yearDiff, $ic ]
			print $LOG join( "; ", map { my $cid = $_->[0]; join( ", ", "'$terms[ $cid ]'", $_->[1], $_->[2], "f:$freqs[ $cid ]" ) } @$sharedTerms ), ".\n";
		}
	}
	print $LOG "Max diff-term simi: $maxDiffTermSimi.";
	if($maxDiffTermSimi > 0){
		print $LOG " Closest: $concept1, '$terms[$concept1]', weight = $w1\t",
				"$concept2, '$terms[$concept2]', weight = $w2\n",
				"LCS: $lcs, '$terms[$lcs]', generalization depths = $leastDepth. ",
				"Attenuation = $attenuation, yearDiff = $yearDiff. ",
				"freq = $freqs[$lcs], IC = $ICs[$lcs], lcsSimi = $lcsSimi\n";
	}
	else{
		print $LOG "\n";
	}
	
	print $LOG scalar keys %$sharedVenues, " shared venues, boost: $venueBoost. ", 
				dumpSortedHash($sharedVenues, undef, undef), "\n";
}

sub calcTermCloseness($$$)
{
	my ($ancestorTree, $i, $j) = @_;

	# @leastDepthPair in the returned tuple of leastCommonSubsumer() is abandoned
	# $leastDepth is the original sum of generalization depth (without attenuation)
	my ($lcs, $leastDepth, $attenuation) = leastCommonSubsumer($ancestorTree, $i, $j, 
												$MAX_LEAST_DEPTH_FOR_COMMON_ANCESTOR);

	if($lcs < 0){
		return ( 0, 0, 0, 0 );
	}
		
	if(! $CALC_SIMI_USE_IC){
		# inversely proportional to the least depth sum to common ancestors
		# when they are the same term, closeness = 1. when $leastDepth = 1, closeness = 1/2...
		return ( 1 / ($leastDepth + 1), $attenuation, $lcs, $leastDepth );
	}
	else{
		if(! defined($ICs[$lcs]) ){
			print $LOG "IC of '$terms[$lcs]' is undefined!\n";
		}
		
		return ( max($ICs[$lcs] - $ICOffset, 0), $attenuation, $lcs, $leastDepth );
	}
}

sub compactConceptVector($$)
{
	my ($ancestorTree, $pConceptVec) = @_;

	my %conceptVecSimple;
	my $conceptID;
	for $conceptID(keys %$pConceptVec){
		# each entry in %$pConceptVec has 4 subkeys: 'w', 'c', 'f' (from year), 't' (to year)
		# only 'w' (weight) is used here. so simplify the vector
		$conceptVecSimple{$conceptID} = $pConceptVec->{$conceptID}{w};
	}
	
	my %mergeMap = mergeNearbyTerms( $ancestorTree, \%conceptVecSimple, 1 );

	my %conceptVec2;
	my $newCID;
	
	for $conceptID(keys %$pConceptVec){
		$newCID = $mergeMap{$conceptID}->[0];
		$conceptVec2{ $newCID }{w} += $pConceptVec->{$conceptID}{w};
		updateYearRange( $conceptVec2{$newCID}, $pConceptVec->{$conceptID}{f}, 
							$pConceptVec->{$conceptID}{t} );
		push @{ $conceptVec2{ $newCID }{tokens} }, @{ $pConceptVec->{$conceptID}{tokens} };
		
		# keep the old concept
		if($newCID != $conceptID){
			$conceptVec2{ $conceptID } = $pConceptVec->{$conceptID};
		}
	}

	return %conceptVec2;
}

# some concepts are extracted based on the same snippet. only one of them should be kept
# removeOverlapTerms(\@sharedTerms, $cv1, $cv2)
sub removeOverlapTerms($$$)
{
	my ($sharedTerms, $cv1, $cv2) = @_;
	
	my @titlesTokensMark1;
	my @titlesTokensMark2;
	my %isConceptCounted;
	my %conflictConcepts;
	my ($conflictICSum, $conflictSimiSum);
	
	# each tuple: [ $concept1, $sharedTermSimi, $yearDiff, $ic ]
	my $sharedTermTuple;
	my ($concept, $sharedTermSimi, $yearDiff, $ic);
	# $titleSN is numbered from 0
	my ($titleSN, $tokenTupleList, $tokenTuple, @tokenList, $tokenList, $tokenSN);
	my $i;
	
	my $traverseTokenTupleList = 
	sub{
		my ($tokenTupleList, $titlesTokensMark, $processor, @args) = @_;
		my $tokenTuple;
		my ($titleSN, $tokenList);
		
		for $tokenTuple(@$tokenTupleList){
			($titleSN, $tokenList) = @$tokenTuple;
			for $tokenSN(@$tokenList){
				&$processor( $titlesTokensMark, $titleSN, $tokenSN, @args );
			}
		}
	};
	
	my $getConflictConcepts =
	sub{
		my ( $titlesTokensMark, $titleSN, $tokenSN, $conflictConcepts ) = @_;
		my ($oldConceptTuple, $oldConcept);
		
		$oldConceptTuple = $titlesTokensMark->[ $titleSN ][$tokenSN];
		if( $oldConceptTuple ){
			$oldConcept = $oldConceptTuple->[0];
			if( $isConceptCounted{ $oldConcept } ){
				$conflictConcepts->{ $oldConcept } = $oldConceptTuple;
			}
		}
	};
	
	my $updateTokensMark = 
	sub{
		my ( $titlesTokensMark, $titleSN, $tokenSN, $newConceptTuple ) = @_;
		my ($oldConceptTuple, $oldConcept, $newConcept);
		
		$oldConceptTuple = $titlesTokensMark->[ $titleSN ][$tokenSN];
		if( $oldConceptTuple ){
			$oldConcept = $oldConceptTuple->[0];
			$isConceptCounted{ $oldConcept } = 0;
		}
		
		$newConcept = $newConceptTuple->[0];
		$titlesTokensMark->[ $titleSN ][$tokenSN] = $newConceptTuple;
		$isConceptCounted{ $newConcept } = 1;
	};
	
	for $sharedTermTuple(@$sharedTerms){
		( $concept, $sharedTermSimi, $yearDiff, $ic ) = @$sharedTermTuple;
		%conflictConcepts = ();
		
		$tokenTupleList = $cv1->{$concept}{tokens};
		&$traverseTokenTupleList( $tokenTupleList, \@titlesTokensMark1, $getConflictConcepts, \%conflictConcepts );
		
		$tokenTupleList = $cv2->{$concept}{tokens};
		&$traverseTokenTupleList( $tokenTupleList, \@titlesTokensMark2, $getConflictConcepts, \%conflictConcepts );

		$conflictICSum 		= sum( 0, map { $_->[3] }  values %conflictConcepts );
		$conflictSimiSum 	= sum( 0, map { $_->[1] }  values %conflictConcepts );
		if( $conflictICSum < $ic || $conflictICSum == $ic && $conflictSimiSum < $sharedTermSimi ){
			$tokenTupleList = $cv1->{$concept}{tokens};
			&$traverseTokenTupleList( $tokenTupleList, \@titlesTokensMark1, $updateTokensMark, $sharedTermTuple );
			
			$tokenTupleList = $cv2->{$concept}{tokens};
			&$traverseTokenTupleList( $tokenTupleList, \@titlesTokensMark1, $updateTokensMark, $sharedTermTuple );
		}
	}
	
	# each tuple: [ $concept1, $sharedTermSimi, $yearDiff, $ic ]
	my @removedTerms = grep { ! $isConceptCounted{ $_->[0] } } @$sharedTerms;
	if(@removedTerms){
		print $LOG "Removed terms: ", join( "\t", map { "$terms[ $_->[0] ] $_->[3]" } @removedTerms ), "\n";
	}
	return grep { $isConceptCounted{ $_->[0] } } @$sharedTerms;
}

our %ConceptVecSimiCache;

sub emptyConceptVecSimiCache
{
	%ConceptVecSimiCache = ();
}

# the probability that the same concept is shared by two clusters by different namesakes
our $MAX_AMBIGUITY_OF_SHARED_CONCEPTS = 1;
our $MAX_AMBIGUITY_OF_SHARED_SINGLE_CONCEPT = 0.5;
our $LOG_MAX_AMBIGUITY_OF_SHARED_CONCEPTS = -log($MAX_AMBIGUITY_OF_SHARED_CONCEPTS);
# though we can calc the prob that a concept is shared between authors, we make the prob stricter
# to filter out some random shares
our $BOOST_SHARE_TERM_CHANCE_FROM_RANDOMNESS = 3;
# previously it's set to the clustering threshold. but when ambig is high and the threshold may be 
# as big as 5 (lei wang) or 20( wei wang). it's too big, so set a reasonable max
our $MAX_EMPTY_CONCEPT_VEC_SIMI_PRIOR = 0.5;
# each weight is at least this value
our $SHARED_CONCEPT_LEAST_IC_WEIGHT_IN_SUM = 0.1;
# two weights add up to at least this value
our $SHARED_CONCEPT_LEAST_IC_WEIGHT_SUM_IN_SUM = 0.3;

our $BOOST_SHARED_TERMS_WEIGHT		= 3;
#our $SCALEDOWN_LCS_TERMS_WEIGHT		= 0.5;

our $MIN_SAME_VENUE_MN_ODDS_RATIO = 0.1;

sub calcConceptVectorSimi($$$$$$$)
{
	# $no1 & $no2 are concept vec UID (unique in one clustering trial)
	# cv_vv*: [ concept vector, venue vector ]
	# cluster*: paper numbers in this cluster. 
	# paper titles, etc. can be retrieved in $context->{pubset} using this number
	my ($context, $no1, $cv_vv1, $cluster1, $no2, $cv_vv2, $cluster2) = @_;

	my $cv1 = $cv_vv1->[0];
	my $vv1 = $cv_vv1->[1];
	my $cv2 = $cv_vv2->[0];
	my $vv2 = $cv_vv2->[1];
	
	my $ancestorTree 	= $context->{ancestorTree};
	my $venueJacThres	= $context->{venueJacThres};
	my $useUnigram		= $context->{useUnigram};
	
	my $emptyConceptVecSimiPrior = min( $context->{emptyConceptVecSimiPrior}, 
										$MAX_EMPTY_CONCEPT_VEC_SIMI_PRIOR );
										
	my $ambig = $context->{ambig};
	my $logAmbig = log($ambig);
	my $freqSumThres = $MC * $MAX_AMBIGUITY_OF_SHARED_SINGLE_CONCEPT / 
							($ambig * $BOOST_SHARE_TERM_CHANCE_FROM_RANDOMNESS);
	
	# the concept-ambiguity is author-ambiguity * concept-probability
	# after taking log, it becomes a sum
	my $ICSumThres = $logAmbig + $LOG_MAX_AMBIGUITY_OF_SHARED_CONCEPTS;
	
	my ($lcs, $sharedTermSimiSum, $lcsSimi, $concept1, $w1, $concept2, $w2);
	$sharedTermSimiSum = 0;

	my $maxDiffTermSimi = 0;
	my $maxsimi = 0;
	my $ICSum = 0;
	my ($ic, $freq);
	my ($freqThres1, $freqThres2, $freqThres);
	
	my $leastDepth;
	my ($diffTermSimi, $diffTermIC);
	my @closestTuple = ( 0 );
	my $attenuation;
	my @sharedTerms;
	my $sharedTermSimi;
	my %sharedTerms;
	my @filteredTerms;
	
	my $uuid = join( ",", sort { $a <=> $b } ($no1, $no2) );

	my ($h1, $h2);
	my $yearDiffDiscount;
	my $yearDiff;
	
	my ($lemmaID, $unigram);
	
	my ($venueName, $venueFreq);
	my %sharedVenues;
	my ($venueBoost, $venueBoost2);

	my $simiTupleRetrievedFromCache = 0;
	
	if($ConceptVecSimiCache{$uuid}){
		@closestTuple = @{ $ConceptVecSimiCache{$uuid} };
		$simiTupleRetrievedFromCache = 1;
	}
	else{
		for $venueName(keys %$vv1){
			if( exists $vv2->{$venueName} ){
				$venueFreq = min( $vv1->{$venueName}, $vv2->{$venueName} );
				$sharedVenues{$venueName} = $venueFreq;
			}
		}
		
		if(! $venueJacThres){
			# try venue expansion and no expansion. choose the better one
			
			if( $USE_CSLR_VERSION == 1 ){
				$venueBoost = isSameCategorical( 0.6, 0.6, 0.6, 0.5, $vv1, $vv2, 
										\&expandSimilarVenues, $MIN_SAME_VENUE_MN_ODDS_RATIO, 4 );
				$venueBoost2 = isSameCategorical( 0.6, 0.6, 0.6, 0.5, $vv1, $vv2, 
													undef, $MIN_SAME_VENUE_MN_ODDS_RATIO, 4 );
			}
			else{
				$venueBoost = isSameCategorical2( 0.6, 0.6, 0.6, $CSLR_VENUE_TOP_LIKELY_FRAC, $vv1, $vv2, 
										\&expandSimilarVenues, $MIN_SAME_VENUE_MN_ODDS_RATIO, 4 );
				$venueBoost2 = isSameCategorical2( 0.6, 0.6, 0.6, $CSLR_VENUE_TOP_LIKELY_FRAC, $vv1, $vv2, 
													undef, $MIN_SAME_VENUE_MN_ODDS_RATIO, 4 );
			}
			
			if($venueBoost < $venueBoost2){
				$venueBoost = $venueBoost2;
			}
		}
		else{
			$venueBoost = jaccard( $vv1, $vv2, 0.003, 0 ) / $venueJacThres;
		}
		
		if($useUnigram){
			for $lemmaID(keys %$cv1){
				$unigram = $lemmaCache[$lemmaID]->[0];
				next if ! exists $gUnigrams{$unigram};
				
				$h1 = $cv1->{$lemmaID};
				
				if( exists $cv2->{$lemmaID} ){
					$h2 = $cv2->{$lemmaID};

					$yearDiff = calcYearRangeDiff($h1, $h2);			
					$yearDiffDiscount = calcYearDiffDiscount($yearDiff);
					
					$sharedTermSimi = $gUnigrams{$unigram}->tfiaf * $h1->{w} * $h2->{w};
					
					$sharedTermSimi *= $yearDiffDiscount;

					$sharedTermSimiSum += $sharedTermSimi;
					
					push @sharedTerms, [ $unigram, $sharedTermSimi, $yearDiff, $gUnigrams{$unigram}->tfiaf ];
				}
			}
			$maxsimi = $sharedTermSimiSum;
			$maxDiffTermSimi = $freqSumThres = $freqThres1 = $freqThres2 = $freqThres = 0;
			$ICSum = $ICSumThres; # cancel this check
		}
		
		else{
			$freqThres1 = getTermFreqThresByAmbig($cv1, $freqSumThres);
			$freqThres2 = getTermFreqThresByAmbig($cv2, $freqSumThres);
			$freqThres 	= min( $freqThres1, $freqThres2 );
			
			$freqSumThres = trunc(2, $freqSumThres);
			
			for $concept1(keys %$cv1){
				$h1 = $cv1->{$concept1};
				
				if( exists $cv2->{$concept1} ){
					$h2 = $cv2->{$concept1};
					
					$yearDiff = calcYearRangeDiff($h1, $h2);			
					$yearDiffDiscount = calcYearDiffDiscount($yearDiff);
					if(! $ICs[$concept1]){
						next;
					}
					$sharedTermSimi = max( $ICs[$concept1] - $ICOffset, 0 ) *
											$h1->{w} * $h2->{w};
					
					$sharedTermSimi *= $yearDiffDiscount;
					$sharedTermSimi = trunc(4, $sharedTermSimi);
					
					if( 1
#						&& min($h1->{w}, $h2->{w}) >= $SHARED_CONCEPT_LEAST_IC_WEIGHT_IN_SUM 
#						&&  $h1->{w} + $h2->{w} >= $SHARED_CONCEPT_LEAST_IC_WEIGHT_SUM_IN_SUM
					){
						$ic = $ICs[$concept1] * $yearDiffDiscount;
						push @sharedTerms, [ $concept1, $sharedTermSimi, $yearDiff, $ic ];
	
						# store them, to avoid the lcs of diff terms is one of shared terms
						$sharedTerms{$concept1} = 1;
					}
				}
			}
	
			for $concept1(keys %$cv1){
				$h1 = $cv1->{$concept1};
				
				for $concept2(keys %$cv2){
					$h2 = $cv2->{$concept2};
					
					$yearDiff = calcYearRangeDiff($h1, $h2);			
					$yearDiffDiscount = calcYearDiffDiscount($yearDiff);
	
					if($concept1 == $concept2){
						next;
					}
					if( $sharedTerms{$concept1} || $sharedTerms{$concept2} ){
						next;
					}
					
					# $attenuation is used to scale down matching weights, not the IC
					( $lcsSimi, $attenuation, $lcs, $leastDepth ) = 
									calcTermCloseness($ancestorTree, $concept1, $concept2);
									
					my $ICDiscount;
					if( defined($leastDepth) ){
						$ICDiscount = ( $GENERALIZATION_DISCOUNT_PER_STEP ** $leastDepth ) * $yearDiffDiscount;
					}
										# it's pointless to count in an lcs which is a shared term
					if($lcsSimi != 0 && ! $sharedTerms{$lcs}){
						$diffTermSimi = $lcsSimi * $attenuation * $cv1->{$concept1}{w} * $cv2->{$concept2}{w};
						
						$diffTermSimi *= $ICDiscount;
					}
					else{
						$diffTermSimi = 0;
					}
						
					if( $maxDiffTermSimi < $diffTermSimi 
#					&& min( $h1->{w}, $h2->{w} ) >= $SHARED_CONCEPT_LEAST_IC_WEIGHT_IN_SUM 
#						&&   $h1->{w} + $h2->{w} >= $SHARED_CONCEPT_LEAST_IC_WEIGHT_SUM_IN_SUM
						&& $freqs[$lcs] <= $freqSumThres ){
							$maxDiffTermSimi = $diffTermSimi;
							$diffTermIC = $ICs[$lcs] * $ICDiscount;
							
							@closestTuple = ($lcs, $lcsSimi, $attenuation, $leastDepth, $concept1, 
											$cv1->{$concept1}{w}, $concept2, $cv2->{$concept2}{w}, $yearDiff);
					}
				}
			}
		}
		
		if(keys %$cv1 == 0){
			if($DEBUG & DBG_CALC_SIMI){
				print $LOG "Cluster $no1 is empty. Similarity of $no1 $no2 is set to $emptyConceptVecSimiPrior\n";
			}
			$maxsimi = $emptyConceptVecSimiPrior;
			# give empty (concept vector) titles a chance to be merged
			$ICSum = $ICSumThres;
		}
		elsif(keys %$cv2 == 0){
			if($DEBUG & DBG_CALC_SIMI){
				print $LOG "Cluster $no2 is empty. Similarity of $no1 $no2 is set to $emptyConceptVecSimiPrior\n";
			}
			$maxsimi = $emptyConceptVecSimiPrior;
			# give empty (concept vector) titles a chance to be merged
			$ICSum = $ICSumThres;
		}
		else{
			if(! $useUnigram){
				@sharedTerms = removeOverlapTerms(\@sharedTerms, $cv1, $cv2);
				my $singleTermFiltered = 0;
				
				if(@sharedTerms == 1){
					my $concept = $sharedTerms[0]->[0];
					my $freq = $freqs[$concept];
					if($freq > $freqThres){
						print $LOG "'$terms[$concept]' freq $freq > thres $freqThres, discarded\n";
						$singleTermFiltered = 1;
					}
				}
				
				if(! $singleTermFiltered){	
					$sharedTermSimiSum 	= sum( 0, map { $_->[1] } @sharedTerms );
					$ICSum 				= sum( 0, map { $_->[3] } @sharedTerms );
				}
				else{
					$sharedTermSimiSum = 0;
					$ICSum = 0;
				}
				
				$maxsimi = $maxDiffTermSimi + $BOOST_SHARED_TERMS_WEIGHT * $sharedTermSimiSum;
				
				if($diffTermIC){
					$ICSum += $diffTermIC;
				}
			}
			# if two non-empty concept vectors have similarity 0, don't raise the similarity
			if($USE_VEC_SIMI_LOWER_BOUND && $maxsimi > 0 && $maxsimi < $emptyConceptVecSimiPrior){
				if($DEBUG & DBG_CALC_SIMI){
					print $LOG "maxsimi $maxsimi < prior $emptyConceptVecSimiPrior, set to $emptyConceptVecSimiPrior\n";
				}
				$maxsimi = $emptyConceptVecSimiPrior;
			}
		}
		$maxsimi *= $venueBoost;
				
		unshift @closestTuple, ($maxsimi, $ICSum, $ICSumThres, \%sharedVenues, $venueBoost, 
									$sharedTermSimiSum, \@sharedTerms, $maxDiffTermSimi,
									$freqSumThres, $freqThres1, $freqThres2, $freqThres);
									
		$ConceptVecSimiCache{$uuid} = [ @closestTuple ];
	}
			# place holder. $_ is useless anyway
#	($maxsimi, $_, $_, $sharedTermSimiSum, $_, $maxDiffTermSimi, $lcs, $lcsSimi, $attenuation, 
#			$leastDepth, $concept1, $w1, $concept2, $w2, $yearDiff) = @closestTuple;

	if($DEBUG & DBG_CALC_SIMI){
		print $LOG "Vec $no1 $no2: simi = $maxsimi\n";

		if($maxsimi == 0){
			print $LOG "Vec $no1: ";
			dumpConceptVenueVec($LOG, $cv_vv1, $useUnigram);
	
			print $LOG "Vec $no2: ";
			dumpConceptVenueVec($LOG, $cv_vv2, $useUnigram);

			dumpSimiTuple(\@closestTuple, $useUnigram);
			print $LOG "Disparate\n\n";
		}
		else{
			if($simiTupleRetrievedFromCache){
				print $LOG "Vec $no1: ";
				dumpConceptVenueVec($LOG, $cv_vv1, $useUnigram);
	
				print $LOG "Vec $no2: ";
				dumpConceptVenueVec($LOG, $cv_vv2, $useUnigram);
			}
			else{
				# params: ($context, $clustNo, $titleset, $conceptVec, $isBriefMode)
				dumpTitleset($context, $no1, $cluster1, $cv_vv1, 1);
				dumpTitleset($context, $no2, $cluster2, $cv_vv2, 1);
			}
			
			print $LOG "Term freq thres for vec $no1: $freqThres1. Vec $no2: $freqThres2. Choose $freqThres\n";
			dumpSimiTuple(\@closestTuple, $useUnigram);
			print $LOG "\n";
		}
	}

	if( ! $useUnigram ){
		# add the impact of the venue boost after the tuple is dumped. it's a quick fix to avoid
		# modifying code in agglomerative()
		$closestTuple[1] = max( $closestTuple[1], log( $closestTuple[4] ) );
		#	if( $closestTuple[4] > 1 ){
		#		$closestTuple[1] += log( $closestTuple[4] ) / 2;
		#	}
	}
	
	return \@closestTuple;
}

# upon calling, @$titleset have been converted to concept vectors in $context->{title_ConceptVectors}
# return [ \%compactVec1, \%venueVec ];
sub titleSetToVector($$$)
{
	my ($context, $clustNo, $titleset) = @_;
	if(!$titleset || !@$titleset){
		return {};
	}

	my $title_ConceptVectors 	= $context->{title_ConceptVectors};
	my $ancestorTree 			= $context->{ancestorTree};
	my $titles					= $context->{titles};
	my $identities				= $context->{identities};
	my $years					= $context->{years};
	my $pubset					= $context->{pubset};
	my $useUnigram				= $context->{useUnigram};
	
	my (%conceptVec1, %compactVec1);
	my $conceptVector;
	my $conceptID;
	my $year;
	
	my $S = @$titleset;
	#my $W = max( 1, log($S) ) / $S;
	#my $W = 1 / sqrt($S);
	my $W = max( 1, log($S) );
#	my $W = $S ** 0.333;
#	my $W = 1;
	
	my $KEPT_TOPN = max($CONCEPT_VEC_TOP_N_TO_CLUST_SIZE_RATIO * $S, $CONCEPT_VEC_LEAST_TOP_N);
	$KEPT_TOPN = min($KEPT_TOPN, $CONCEPT_VEC_MOST_TOP_N);

	my $titleID;

	my $hashCutoff;

	if($DEBUG & DBG_CALC_SIMI){
		print $LOG "Cluster $clustNo:\n";
		print $LOG "Size: $S, weight: $W\n";
	}

	my %venueVec;
	my $pub;
	my $titleSN = 0;
	
	for $titleID(@$titleset){
		$conceptVector = $title_ConceptVectors->[$titleID];
		$pub = $pubset->[$titleID];
		$year = $years->[$titleID];
		
		if($pub->venue){
			$venueVec{$pub->venue}++;
		}
		else{
			$venueVec{'UNKNOWN'}++;
		}
		
		for $conceptID( keys %$conceptVector ){
			# the conceptVector of each title actually isn't like other conceptVectors 
			# such as $conceptVec1. Each hash value is a pair: [ weight, token_indices ]
			### OBSOLETE in $conceptVec1, each conceptID has 3 subkeys: 'w', 'f', 't'
			# in $conceptVec1, each conceptID has 5 subkeys: 'w', 'c', 'f' (from year), 't' (to year)
			# 'tokens': [ titleID, token IDs in this title ]. same tokens spawn more than 1
			# concepts. check 'tokens' to avoid all of them being counted in
			$conceptVec1{$conceptID}{w} += $conceptVector->{$conceptID}->[0];
			push @{ $conceptVec1{$conceptID}{tokens} }, [ $titleSN, $conceptVector->{$conceptID}->[1] ];
			$conceptVec1{$conceptID}{c}++;
			updateYearRange( $conceptVec1{$conceptID}, $year );
		}

		if( $DEBUG & DBG_CALC_SIMI ){
			if($identities->[$titleID]){
				print $LOG "$identities->[$titleID]. ";
			}
			print $LOG "Title $titleID: $titles->[$titleID]\n";
		}
		
		$titleSN++;
	}

	if($DEBUG & DBG_CALC_SIMI){
		print $LOG "Original: ";
		dumpConceptVec($LOG, \%conceptVec1, $useUnigram);
	}

	for $conceptID( keys %conceptVec1 ){
		$conceptVec1{$conceptID}{w} /= sqrt( $conceptVec1{$conceptID}{c} ) * $W;
	}
		
	if($DEBUG & DBG_CALC_SIMI){
		print $LOG "Scaled: ";
		dumpConceptVec($LOG, \%conceptVec1, $useUnigram);
	}
	
	if( scalar keys %conceptVec1 > $KEPT_TOPN ){
		if($DEBUG & DBG_CALC_SIMI){
			%conceptVec1 = hashTopN( \%conceptVec1, $KEPT_TOPN, sub{ $_[0]->{w} }, 
							sub{ my ($cutoffCount, $biggestCutK, $biggestCutV) = @_;
								 print $LOG "$cutoffCount elems cut off. ",
								 			"Biggest: '", 
								 			$useUnigram ? $lemmaCache[$biggestCutK]->[0] : $terms[$biggestCutK],
								 			"' => $biggestCutV\n";
							} );
			print $LOG "Shortened: ";
			dumpConceptVec($LOG, \%conceptVec1, $useUnigram);
		}
		else{
			%conceptVec1 = hashTopN( \%conceptVec1, $KEPT_TOPN, sub{ $_[0]->{w} } );
		}
	}

	if($useUnigram){
		return [ \%conceptVec1, \%venueVec ];
	}

# compacting eliminates some common terms (a term in one vec becomes a more general term), 
# which is not desirable

	%compactVec1 = compactConceptVector($ancestorTree, \%conceptVec1);
	if($DEBUG & DBG_CALC_SIMI){
		print $LOG "Compacted: ";
		dumpConceptVec($LOG, \%compactVec1, $useUnigram);
		print $LOG "\n";
	}

	# a quick fix to add %venueVec to the returned concept vector
	return [ \%compactVec1, \%venueVec ];

}

sub calcTitleSetSimi($$$$$)
{
	my ($context, $no1, $c1, $no2, $c2) = @_;

	if(!$c1 || !$c2){
		return 0;	# empty set should never be similar to a non-empty set
	}

	my $ancestorTree = $context->{ancestorTree};

	my ($conceptVec1, $conceptVec2);

	$conceptVec1 = titleSetToVector($context, $c1, 1);
	$conceptVec2 = titleSetToVector($context, $c1, 2);

	my $simi = calcConceptVectorSimi( $ancestorTree, $no1, $conceptVec1, $c1, $no2, $conceptVec2, $c2 );

	return $simi;
}

sub cmdline
{
	my %args = @_;

	my ($treeRoots, $ancestorTree, $inheritCount, $dumpFilename, $depthByBatch,
			$attenuateByBatch, $recAttenuateByBatch);

	$treeRoots 				= $args{rootterms};
	$ancestorTree 			= $args{ancestorTree} 		|| \@ancestorTree;
	$inheritCount			= $args{inheritCount} 		|| \@inheritCount;
	$depthByBatch			= $args{depthByBatch} 		|| \@depthByBatch;
	$attenuateByBatch		= $args{attenuateByBatch} 	|| \@attenuateByBatch;
	$recAttenuateByBatch	= $args{recAttenuateByBatch}	|| \@recAttenuateByBatch;

	$dumpFilename = $args{dumpFilename};

	my $input;
	my ($cmd, $cmdparam, $term);
	my @givenTerms;
	my $parent;
	my $redirect;
	my $titleID = 0;

	my $terminal = Term::ReadLine->new();
	my $prompt = "CMD>";
	
#	$SIG{INT} = \&NO_OP;

	while(1){
		$input = $terminal->readline($prompt);
		trim($input);

		if($input =~ /^([aeidhw]|[ctm](\d*)|raw|lcs|train|dumpic|loadic|af|afa|df|uc|checkfreq|eancestor|sancestor|lancestor|stop|ex|ent)(\s+([^>]+)(>(.+))?|$)/){
			$cmd = $1;
			$cmdparam = $2;
			$term = $4 || "";
			trim($term);
			$redirect = $6 || "";

			$cmd =~ s/\d+$//;
			trim($redirect);

			given($cmd){
				when(/^h$/){
					print STDERR <<HELP;
Available commands:
a term
	Trace from term back to ROOT
c term
	Dump the subtree rooted at term
e term1[,term2...]
	Exclude term1[,term2...] when do dumping
i term1[,term2...]
	Include term1[,term2...] when do dumping
w category1  term1[,term2...]
	Only include term1[,term2...] under category1
l term1  term2
	Find the least common subsumer of term1 and term2
d
	Dump the whole concept net into '$dumpFilename'
HELP

				}

				when(/^a$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					dumpAncestors( rootterm => $term, ancestorTree => $ancestorTree,
									dumpFilename => $redirect);
				}
				when(/^c$/){
					$cmdparam ||= 3;
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					my @tempAncestorTree;
					dumpChildren( rootterms => [ $term ], ancestorTree => \@tempAncestorTree,
									dumpFilename => $redirect, depth => $cmdparam );
				}
				when(/^t$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					dumpChildren( rootterms => [ $term ], treeview => 1,
									dumpFilename => $redirect, depth => $cmdparam);
				}
				when(/^e$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					@givenTerms = split /(?<=[^\\]),\s*/, $term;
					@givenTerms = map { s/\\//g; $_ } @givenTerms;
					exclude(1, @givenTerms);
				}
				when(/^ex$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					@givenTerms = split /(?<=[^\\]),\s*/, $term;
					@givenTerms = map { s/\\//g; $_ } @givenTerms;
					excludeX(1, @givenTerms);
				}
				when(/^stop$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					@givenTerms = split /(?<=[^\\]),\s*/, $term;
					@givenTerms = map { s/\\//g; $_ } @givenTerms;
					addStopterm(1, @givenTerms);
				}
				when(/^i$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					@givenTerms = split /(?<=[^\\]),\s*/, $term;
					@givenTerms = map { s/\\//g; $_ } @givenTerms;
					include(@givenTerms);
				}
				when(/^w$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					($parent, $term) = split /  /, $term;
					$term ||= "";
					exclude4whitelist(1, { $parent => $term } );
				}
				when(/^raw$/){
					if(!$term){
						print STDERR "Code snippet is not given.\n";
						break;
					}
					eval $term;
					print STDERR "\n";
					print STDERR "$@\n" if $@;
				}
				when(/^lcs$/){
					if(! $term){
						print STDERR "Terms are not given.\n";
						break;
					}
					@givenTerms = split /  /, $term;
					if(@givenTerms == 1){
						print STDERR "Only one term is given.\n";
						break;
					}
					if(@givenTerms > 2){
						print STDERR "Too many terms (", scalar @givenTerms, ") are given.\n";
						break;
					}
					my @ids = terms2IDs(\@givenTerms);
					if(!@ids){
						break;
					}

					dumpAncestors(rootterm => $givenTerms[0], ancestorTree => $ancestorTree,
									simpleMode => 1);
					dumpAncestors(rootterm => $givenTerms[1], ancestorTree => $ancestorTree,
									simpleMode => 1);

					my ($lcs, $leastDepth, $attenuation) = leastCommonSubsumer($ancestorTree, @ids);
					print $tee "LCS: $terms[$lcs]. Least depth sum: $leastDepth. Attenuation: $attenuation.";
					if(defined($ICs[$lcs]) && $ICs[$lcs] >= 0){
						print $tee " IC: $ICs[$lcs]";
					}
					print $tee "\n";
				}

				when(/^d$/){
					dumpChildren( rootterms => $treeRoots,
									ancestorTree => $ancestorTree, dumpFilename => $dumpFilename );
				}
				when(/^m$/){
					my $title = $term;
					if(! $title){
						print STDERR "Title is not given.\n";
						break;
					}
					my (@lemmaIDs, @stopwordGapNums, @stopwordGapWeights);
					extractTitleTokens( $title, \@lemmaIDs, \@stopwordGapNums, \@stopwordGapWeights );
					if(!@lemmaIDs){
						print STDERR "Title doesn't contain any valid word.\n";
						break;
					}
					print $tee "Keywords: ",
								quoteArray(map { $lemmaCache[$_]->[0] } @lemmaIDs), "\n\n";

					if(! $cmdparam){
						my %maxMatchScores = matchTitle($ancestorTree, $titleID++, $title, 
														$DEFAULT_TERM_MATCH_WEIGHT_THRES, 0);
						my @postings = sort { $maxMatchScores{$b}->[0]
													<=>
											  $maxMatchScores{$a}->[0]
											} keys %maxMatchScores;
						my $posting;
						for $posting(@postings){
							print $tee "$terms[$posting], $maxMatchScores{$posting}->[0]: ",
								quoteArray( tokenIDs2words( \@lemmaIDs, $maxMatchScores{$posting}->[1] ) ),
										"\n";
						}
					}
					else{
						my $oldDEBUG = $DEBUG;
						$DEBUG = $DEBUG | DBG_MATCH_TITLE | DBG_TRACK_ADD_FREQ;
						matchTitle($ancestorTree, $title, $cmdparam, $DEFAULT_TERM_MATCH_WEIGHT_THRES, 0);
						$DEBUG = $oldDEBUG;
					}
				}
				when(/^dumpic$/){
					my $ICFilename = $term;
					saveNetIC(filename => $ICFilename);
				}
				when(/^loadic$/){
					my $ICFilename = $term;
					loadNetIC(filename => $ICFilename);
				}
				when(/^af$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					dumpAncestors( rootterm => $term, ancestorTree => $ancestorTree,
									dumpFilename => $redirect, printFreq => 1 );
				}
				when(/^afa$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					dumpAncestors( rootterm => $term, ancestorTree => $ancestorTree,
									dumpFilename => $redirect, printFreq => 1, uplevel => -1 );
				}
				when(/^df$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					@givenTerms = split /(?<=[^\\]),\s*/, $term;
					@givenTerms = map { s/\\//g; $_ } @givenTerms;
					my @ids = terms2IDs(\@givenTerms);
					@ids = sort { $freqs[$b] <=> $freqs[$a] } grep { $freqs[$_] } @ids;
					print STDERR map { "$_\t$terms[$_]\t$freqs[$_]\n" } @ids;
				}
				# list the unique children of a term
				when(/^uc$/){
					if(!$term){
						print STDERR "Term is not given.\n";
						break;
					}
					listUniqueChildren(\@conceptNet, $ancestorTree, $term);
				}
				when(/^checkfreq$/){
					my $proportion = $term;
					if($proportion >= 1 || $proportion <= 0){
						print STDERR "Invalid proportion: should be in (0, 1)\n";
					}
					else{
						if($MC == 0){
							print STDERR "MC=0, please load IC file first\n";
						}
						checkAbnormalFreq($proportion, $redirect);
					}
				}
				when(/^train$/){
					my $dblpFilename = $term;
					trainDBLPFile($dblpFilename, 0.3);
				}
				when(/^eancestor$/){
					enumAncestors(\@conceptNet, $treeRoots, $ancestorTree, $inheritCount,
										$depthByBatch, $attenuateByBatch, $recAttenuateByBatch, 1);
				}
				when(/^sancestor$/){
					my $ancestorFileName = $term;
					saveAncestors(\@ancestorTree, $ancestorFileName);
				}
				when(/^lancestor$/){
					my $ancestorFileName = $term;
					loadAncestors(\@conceptNet, $treeRoots, $ancestorTree, $inheritCount, $ancestorFileName);
				}
				when(/^ent$/){
					my $entropyFilename = $term;
					calcUnigramEntropies($entropyFilename);
				}
			}
		}
		elsif($input){
			print STDERR "Invalid command.\n";
			next;
		}
		else{
			print STDERR "Are you sure you want to exit? (y/N) ";
			$input = <STDIN>;
			if($input =~ /^y$/i){
				last;
			}
		}
	}

#	$SIG{INT} = undef;
}

1;
