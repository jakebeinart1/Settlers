//! Fixture generator for the pinned, unchanged catan-env v1 encoder.
//! Copy as catan-env/examples/empires_observation_fixture.rs in the isolated
//! research checkout, then cargo run --release -p catan-env --example
//! empires_observation_fixture. stdout is JSON; no training or source patch.
//! Add `-- --compounds` for named, sequential compound-decision fixtures.
//! Compound roots use legal seeded setup/turn transitions and explicit card
//! inventories; every emitted stage advances through unchanged execute_action.
use catan_core::board::topology;
use catan_core::game::{Action, CatanGame, GamePhase, TurnPhase};
use catan_core::players::{Player, RandomPlayer};
use catan_core::state::{DEV_KNIGHT, DEV_ROAD_BUILDING};
use catan_env::codec::encode_action;
use catan_env::obs::{encode_obs, Visibility, OBS_DIM};

fn position(game: &CatanGame) -> String {
    let s = &game.state;
    let seat = game.current_player();
    let mut obs = vec![0.0f32; OBS_DIM];
    encode_obs(game, seat, Visibility::Perfect, &mut obs);
    let remaining = game.pending_discards.get(game.discard_idx)
        .filter(|(p, _)| *p == seat).map(|(_, count)| *count).unwrap_or(0);
    format!(concat!(
        "{{\"players\":{},\"seat\":{},\"turnOwner\":{},\"turn\":{},",
        "\"gamePhase\":{},\"turnPhase\":{},\"target\":{},\"dice\":{},",
        "\"hasRolled\":{},\"roadsToPlace\":{},\"discardsRemaining\":{},\"trades\":{},",
        "\"tileResources\":{:?},\"tileNumbers\":{:?},\"portTypes\":{:?},",
        "\"vertices\":{:?},\"edges\":{:?},\"resources\":{:?},\"devCards\":{:?},",
        "\"bought\":{:?},\"knights\":{:?},\"bank\":{:?},\"robber\":{},",
        "\"longest\":{},\"largest\":{},\"tileVertices\":{:?},",
        "\"edgeVertices\":{:?},\"portVertices\":{:?},\"features\":{:?}}}"),
        s.num_players, seat, s.current_player, s.turn, game.game_phase as u8,
        game.turn_phase as u8, s.victory_target, s.dice_roll, s.has_rolled,
        game.roads_to_place, remaining, game.trades_proposed_this_turn,
        s.tile_resources,s.tile_numbers,s.port_types,s.vertices,s.edges,
        s.resources,s.dev_cards,s.dev_cards_bought_this_turn,s.knights_played,
        s.bank,s.robber_tile,s.longest_road_player,s.largest_army_player,
        topology().tile_vertices,topology().edge_vertices,topology().port_vertices,obs)
}

fn sampled_positions() {
    for n in [3, 4] {
        let mut game = CatanGame::new(n, 419);
        let mut player = RandomPlayer::new(501);
        let mut valid: Vec<Action> = Vec::new();
        for step in 0..=600 {
            if game.is_game_over() { break; }
            // Trading needs a separately declared adapter; don't certify an
            // absent offer as equivalent to the foreign single-offer protocol.
            if (step < 2 * n * 2 || step % 40 == 0) && game.trade_offer.is_none() {
                println!("{}", position(&game));
            }
            game.fill_valid_actions(&mut valid);
            assert!(!valid.is_empty());
            let action = player.choose_action(&game, &valid);
            assert!(game.execute_action(&action));
        }
    }
}

fn compound_step(game: &mut CatanGame, case: &str, stage: &str, action: Action) {
    let valid = game.valid_actions();
    assert!(valid.len() > 1, "{case}/{stage} must reach the encoder, not a singleton mask");
    assert!(valid.contains(&action), "{case}/{stage} action is not legal");
    println!("{{\"case\":\"{case}\",\"stage\":\"{stage}\",\"seed\":{},\"action\":{},\"position\":{}}}",
             game.state.seed, encode_action(game, &action), position(game));
    assert!(game.execute_action(&action));
}

fn compound_root(players: usize, seed: u64) -> CatanGame {
    let mut game = CatanGame::new(players, seed);
    let mut player = RandomPlayer::new(seed + 82);
    while game.game_phase != GamePhase::Playing {
        let action = player.choose_action(&game, &game.valid_actions());
        assert!(game.execute_action(&action));
    }
    // Reach a nonzero turn owner through actual completed turns.
    for seat in 0..players - 1 {
        assert!(game.execute_action(&Action::RollDice { player: seat as u8, forced: Some(2) }));
        assert!(game.execute_action(&Action::EndTurn { player: seat as u8 }));
    }
    set_hands(&mut game, [[0; 5]; 4]);
    game
}

fn set_hands(game: &mut CatanGame, hands: [[i16; 5]; 4]) {
    game.state.resources = hands;
    for resource in 0..5 {
        game.state.bank[resource] = 19 - hands.iter().map(|hand| hand[resource]).sum::<i16>();
        assert!(game.state.bank[resource] >= 0);
    }
}

fn road_building(players: usize) {
    let mut game = compound_root(players, 419);
    let player = game.current_player() as u8;
    assert!(game.execute_action(&Action::RollDice { player, forced: Some(2) }));
    set_hands(&mut game, [[0; 5]; 4]);
    // One old playable card plus one bought this turn exercises both blocks.
    game.state.dev_cards[player as usize][DEV_ROAD_BUILDING] = 2;
    game.state.dev_cards_bought_this_turn[DEV_ROAD_BUILDING] = 1;
    compound_step(&mut game, "road-building", "root", Action::PlayRoadBuilding { player });
    let first = game.valid_actions().into_iter().find(|action| {
        let mut next = game.clone();
        next.execute_action(action) && next.turn_phase == TurnPhase::RoadBuilding
            && next.valid_actions().len() > 1
    }).expect("first road with a non-singleton second road mask");
    compound_step(&mut game, "road-building", "first-road", first);
    let second = game.valid_actions()[0];
    compound_step(&mut game, "road-building", "second-road", second);
    assert_eq!(game.turn_phase, TurnPhase::Main);
}

fn knight_root(players: usize, before_roll: bool, seed: u64) -> CatanGame {
    let mut game = compound_root(players, seed);
    let player = game.current_player() as u8;
    if !before_roll {
        assert!(game.execute_action(&Action::RollDice { player, forced: Some(2) }));
    }
    let mut hands = [[0; 5]; 4];
    for seat in 0..players - 1 { hands[seat] = [1, 2, 0, 0, 0]; }
    set_hands(&mut game, hands);
    game.state.dev_cards[player as usize][DEV_KNIGHT] = 1;
    game.state.knights_played[player as usize] = 2;
    game
}

fn knight(players: usize, before_roll: bool) {
    // Find a seeded legal setup with two opponents sharing a robber tile;
    // do not fabricate settlements or bypass upstream's cached topology.
    let (mut game, movement) = (419..519).find_map(|seed| {
        let root = knight_root(players, before_roll, seed);
        let mut staged = root.clone();
        let player = root.current_player() as u8;
        assert!(staged.execute_action(&Action::PlayKnight { player }));
        staged.valid_actions().into_iter().find(|action| {
            let mut next = staged.clone();
            next.execute_action(action) && next.turn_phase == TurnPhase::RobberSteal
                && next.valid_actions().len() > 1
        }).map(|movement| (root, movement))
    }).expect("robber tile with two resource-holding victims");
    let player = game.current_player() as u8;
    let case = if before_roll { "knight-pre-roll" } else { "knight-main" };
    compound_step(&mut game, case, "root", Action::PlayKnight { player });
    compound_step(&mut game, case, "move-robber", movement);
    let victim = *game.valid_actions().last().unwrap();
    compound_step(&mut game, case, "choose-victim", victim);
    assert_eq!(game.turn_phase, if before_roll { TurnPhase::MustRoll } else { TurnPhase::Main });
}

fn multi_discard(players: usize) {
    let mut game = compound_root(players, 419);
    let owner = game.current_player() as u8;
    let mut hands = [[0; 5]; 4];
    hands[0] = [4, 4, 0, 0, 0];
    hands[1] = [0, 4, 4, 0, 0];
    set_hands(&mut game, hands);
    assert!(game.execute_action(&Action::RollDice { player: owner, forced: Some(7) }));
    for player in [0, 1] {
        assert_eq!(game.current_player(), player as usize);
        assert_ne!(player, owner);
        let case = format!("discard-seat-{player}");
        // Alternating types keeps every sequential discard mask non-singleton.
        for (index, resource) in [player, player + 1, player, player + 1].into_iter().enumerate() {
            compound_step(&mut game, &case, &format!("discard-{}", index + 1),
                          Action::DiscardResource { player, resource });
        }
    }
    assert_eq!(game.turn_phase, TurnPhase::RobberMove);
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() { sampled_positions(); return; }
    assert_eq!(args, ["--compounds"], "expected no arguments or --compounds");
    for players in [3, 4] {
        road_building(players);
        knight(players, true);
        knight(players, false);
        multi_discard(players);
    }
}
