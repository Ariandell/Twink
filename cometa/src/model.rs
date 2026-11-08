use std::time::{Duration, Instant};

pub const FLIP_SECONDS: f32 = 0.6;
pub const PERSPECTIVE: f32 = 1500.0;

// Same cubic-bezier(.4,.2,.2,1) as the original site and Flutter 0.3.18.
pub fn ease(t: f32) -> f32 {
    let sample = |u: f32, a: f32, b: f32| {
        3.0 * (1.0 - u).powi(2) * u * a + 3.0 * (1.0 - u) * u * u * b + u.powi(3)
    };
    let (mut lo, mut hi) = (0.0, 1.0);
    for _ in 0..24 {
        let mid = (lo + hi) / 2.0;
        if sample(mid, 0.4, 0.2) < t.clamp(0.0, 1.0) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    sample((lo + hi) / 2.0, 0.2, 1.0)
}

#[derive(Debug, Clone)]
pub struct Motion {
    from: f32,
    pub target: f32,
    started: Instant,
    duration: Duration,
}
impl Motion {
    pub fn new(now: Instant) -> Self {
        Self {
            from: 0.0,
            target: 0.0,
            started: now,
            duration: Duration::ZERO,
        }
    }
    pub fn value(&self, now: Instant) -> f32 {
        if self.duration.is_zero() {
            return self.target;
        }
        let t =
            now.saturating_duration_since(self.started).as_secs_f32() / self.duration.as_secs_f32();
        if t >= 1.0 {
            self.target
        } else {
            self.from + (self.target - self.from) * ease(t)
        }
    }
    pub fn active(&self, now: Instant) -> bool {
        now.saturating_duration_since(self.started) < self.duration
    }
    pub fn retarget(&mut self, target: f32, now: Instant, reduced: bool) {
        self.from = self.value(now);
        self.target = target.clamp(0.0, 1.0);
        self.started = now;
        self.duration = if reduced {
            Duration::ZERO
        } else {
            Duration::from_secs_f32(FLIP_SECONDS * (self.target - self.from).abs())
        };
    }
}

#[derive(Clone, Copy)]
pub struct Word {
    pub german: &'static str,
    pub translation: &'static str,
    pub forms: &'static str,
    pub examples: &'static [&'static str],
}
pub const WORDS: &[Word] = &[
    Word {
        german: "einsammeln",
        translation: "собирать",
        forms: "sammelt ein, sammelte ein, hat eingesammelt",
        examples: &[
            "»Ich erinnere mich an Leute, die am Straßenrand warteten, um Pferdeäpfel einzusammeln«, sagte Ligur.",
            "Der Lehrer sammelt die Hefte ein. Wir haben im Wald Pilze eingesammelt.",
        ],
    },
    Word {
        german: "vollbringen",
        translation: "совершать, осуществлять",
        forms: "vollbringt, vollbrachte, hat vollbracht",
        examples: &[
            "Er brauchte Jahre, um diese Leistung zu vollbringen, und die Vorbereitungen umfassten: Datenmanipulationen in drei verschiedenen Computern, zwei Einbrüche und eine Bestechung, für die er allerdings nur einen bescheidenen Betrag verwendete.",
        ],
    },
    Word {
        german: "der Hügel, die Hügel",
        translation: "холм",
        forms: "",
        examples: &[
            "Wir gehen auf einen Hügel.",
            "Auf dem Hügel steht ein Haus.",
        ],
    },
];

pub struct Session {
    pub index: usize,
    pub outgoing: Option<usize>,
    pub motion: Motion,
    pub ratings: Vec<(usize, u8)>,
    pub reduced: bool,
    pub first_back: bool,
    pub finished: bool,
    pub settings: bool,
    pub started: Instant,
}
impl Session {
    pub fn new(now: Instant) -> Self {
        Self {
            index: 0,
            outgoing: None,
            motion: Motion::new(now),
            ratings: vec![],
            reduced: false,
            first_back: false,
            finished: false,
            settings: false,
            started: now,
        }
    }
    pub fn flip(&mut self, now: Instant) {
        if self.finished {
            return;
        }
        if self.outgoing.is_some() && self.motion.active(now) {
            return;
        }
        self.outgoing = None;
        self.motion
            .retarget(1.0 - self.motion.target, now, self.reduced);
    }
    pub fn rate(&mut self, rating: u8, now: Instant) {
        if !(1..=6).contains(&rating) || self.finished || self.motion.active(now) {
            return;
        }
        self.ratings.push((self.index, rating));
        if self.index + 1 == WORDS.len() {
            self.finished = true;
            return;
        }
        self.outgoing = Some(self.index);
        self.index += 1;
        self.motion
            .retarget(if self.first_back { 1.0 } else { 0.0 }, now, self.reduced);
    }
    pub fn visible_word(&self, now: Instant) -> usize {
        if self.motion.active(now)
            && ((self.motion.value(now) >= 0.5 && !self.first_back)
                || (self.motion.value(now) < 0.5 && self.first_back))
        {
            self.outgoing.unwrap_or(self.index)
        } else {
            self.index
        }
    }
    pub fn reset(&mut self, now: Instant) {
        *self = Self::new(now);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn curve_matches_reference_points() {
        assert!((ease(0.0)).abs() < 0.00001);
        assert!((ease(1.0) - 1.0).abs() < 0.00001);
        assert!(ease(0.5) > 0.7);
    }
    #[test]
    fn interrupted_flip_is_continuous() {
        let n = Instant::now();
        let mut m = Motion::new(n);
        m.retarget(1.0, n, false);
        let half = n + Duration::from_millis(200);
        let before = m.value(half);
        m.retarget(0.0, half, false);
        assert!((m.value(half) - before).abs() < 0.00001);
        assert_eq!(m.value(n + Duration::from_secs(1)), 0.0);
    }
    #[test]
    fn rating_keeps_old_translation_until_new_front_is_visible() {
        let n = Instant::now();
        let mut s = Session::new(n);
        s.flip(n);
        let r = n + Duration::from_secs(1);
        s.rate(5, r);
        assert_eq!(s.index, 1);
        assert_eq!(s.visible_word(r), 0);
        assert_eq!(s.visible_word(r + Duration::from_secs(1)), 1);
    }
    #[test]
    fn rating_during_motion_cannot_skip_words() {
        let n = Instant::now();
        let mut s = Session::new(n);
        s.flip(n);
        s.rate(6, n);
        assert_eq!(s.index, 0);
        assert!(s.ratings.is_empty());
    }
    #[test]
    fn last_card_completes_once() {
        let n = Instant::now();
        let mut s = Session::new(n);
        for _ in 0..5 {
            s.rate(6, n);
        }
        assert!(s.finished);
        assert_eq!(s.ratings.len(), 3);
    }
    #[test]
    fn reduced_motion_is_immediate() {
        let n = Instant::now();
        let mut m = Motion::new(n);
        m.retarget(1.0, n, true);
        assert_eq!(m.value(n), 1.0);
        assert!(!m.active(n));
    }
    #[test]
    fn translation_first_keeps_old_front_during_rating_return() {
        let n = Instant::now();
        let mut s = Session::new(n);
        s.first_back = true;
        s.rate(5, n);
        assert_eq!(s.visible_word(n), 0);
        let settled = n + Duration::from_secs(1);
        assert_eq!(s.visible_word(settled), 1);
        s.flip(settled);
        assert_eq!(s.visible_word(settled + Duration::from_secs(1)), 1);
    }
}
