//! Fixture generator for the pinned, unchanged catan-env v1 encoder.
//! Copy as catan-env/examples/empires_observation_fixture.rs in the isolated
//! research checkout, then cargo run --release -p catan-env --example
//! empires_observation_fixture. stdout is JSON; no training or source patch.
use catan_core::board::topology;
use catan_core::game::{Action, CatanGame};
use catan_core::players::{Player, RandomPlayer};
use catan_env::obs::{encode_obs, Visibility, OBS_DIM};

fn emit(game: &CatanGame) {
    let s = &game.state;
    let seat = game.current_player();
    let mut obs = vec![0.0f32; OBS_DIM];
    encode_obs(game, seat, Visibility::Perfect, &mut obs);
    let remaining = game.pending_discards.get(game.discard_idx)
        .filter(|(p, _)| *p == seat).map(|(_, count)| *count).unwrap_or(0);
    println!(concat!(
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
        topology().tile_vertices,topology().edge_vertices,topology().port_vertices,obs);
}

fn main() {
    for n in [3, 4] {
        let mut game = CatanGame::new(n, 419);
        let mut player = RandomPlayer::new(501);
        let mut valid: Vec<Action> = Vec::new();
        for step in 0..=600 {
            if game.is_game_over() { break; }
            // Trading needs a separately declared adapter; don't certify an
            // absent offer as equivalent to the foreign single-offer protocol.
            if (step < 2 * n * 2 || step % 40 == 0) && game.trade_offer.is_none() {
                emit(&game);
            }
            game.fill_valid_actions(&mut valid);
            assert!(!valid.is_empty());
            let action = player.choose_action(&game, &valid);
            assert!(game.execute_action(&action));
        }
    }
}
