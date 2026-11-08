use crate::model::{PERSPECTIVE, Session, WORDS};
use skia_safe::{
    self as sk, Canvas, Color, Paint, Picture, PictureRecorder, RRect, Rect, TileMode,
    textlayout::{
        FontCollection, Paragraph, ParagraphBuilder, ParagraphStyle, TextStyle,
        TypefaceFontProvider,
    },
};
use std::{
    collections::HashMap,
    path::Path,
    time::{Duration, Instant},
};

const WHITE: Color = Color::WHITE;
const MUTED: Color = Color::from_rgb(156, 160, 170);
fn rgba(r: u8, g: u8, b: u8, a: u8) -> Color {
    Color::from_argb(a, r, g, b)
}
fn paint(color: Color) -> Paint {
    let mut p = Paint::default();
    p.set_anti_alias(true).set_color(color);
    p
}
fn linear(points: ((f32, f32), (f32, f32)), colors: &[Color]) -> Option<sk::Shader> {
    sk::gradient_shader::linear(points, colors, None, TileMode::Clamp, None, None)
}
fn rect(x: f32, y: f32, w: f32, h: f32) -> Rect {
    Rect::from_xywh(x, y, w, h)
}
fn round(c: &Canvas, r: Rect, radius: f32, color: Color) {
    c.draw_rrect(RRect::new_rect_xy(r, radius, radius), &paint(color));
}

pub struct Layout {
    pub card: Rect,
    pub ratings: [Rect; 6],
    pub nav: Rect,
    pub widget: Rect,
}
impl Layout {
    pub fn new(width: f32, height: f32) -> Self {
        let card = rect(12.0, 160.0, width - 24.0, 280.0);
        let nav = rect(28.0, height - 68.0, width - 56.0, 56.0);
        let widget = rect(12.0, height - 156.0, width - 24.0, 76.0);
        let y = 460.0;
        let button_h = ((widget.top - 12.0 - y - 24.0) / 3.0).max(40.0);
        let bw = (width - 36.0) / 2.0;
        let ratings = std::array::from_fn(|i| {
            rect(
                12.0 + (i % 2) as f32 * (bw + 12.0),
                y + (i / 2) as f32 * (button_h + 12.0),
                bw,
                button_h,
            )
        });
        Self {
            card,
            ratings,
            nav,
            widget,
        }
    }
}

pub struct Renderer {
    fonts: FontCollection,
    paragraphs: HashMap<String, Paragraph>,
    faces: HashMap<(usize, bool, u32), Picture>,
    icons: HashMap<&'static str, Vec<sk::Path>>,
}
impl Renderer {
    pub fn new() -> Self {
        let mgr = sk::FontMgr::new();
        let mut provider = TypefaceFontProvider::new();
        for (family, bytes) in [
            (
                "Outfit",
                include_bytes!("../../android/assets/fonts/outfit-variable.ttf").as_slice(),
            ),
            (
                "Roboto",
                include_bytes!("../../android/assets/fonts/roboto-regular.ttf").as_slice(),
            ),
            (
                "Roboto",
                include_bytes!("../../android/assets/fonts/roboto-bold.ttf").as_slice(),
            ),
            (
                "Roboto",
                include_bytes!("../../android/assets/fonts/roboto-italic.ttf").as_slice(),
            ),
        ] {
            let face = mgr.new_from_data(bytes, None).expect("bundled font");
            provider.register_typeface(face, Some(family));
        }
        let mut fonts = FontCollection::new();
        fonts.set_default_font_manager(sk::FontMgr::from(provider), Some("Roboto"));
        let mut icons = HashMap::new();
        for (name, source) in [
            ("back", include_str!("../../android/assets/icons/back.svg")),
            (
                "volume",
                include_str!("../../android/assets/icons/volume.svg"),
            ),
            (
                "settings",
                include_str!("../../android/assets/icons/settings.svg"),
            ),
            ("edit", include_str!("../../android/assets/icons/edit.svg")),
            ("star", include_str!("../../android/assets/icons/star.svg")),
            ("user", include_str!("../../android/assets/icons/user.svg")),
            ("book", include_str!("../../android/assets/icons/book.svg")),
            ("play", include_str!("../../android/assets/icons/play.svg")),
            (
                "upload",
                include_str!("../../android/assets/icons/upload.svg"),
            ),
        ] {
            let document = roxmltree::Document::parse(source).expect("bundled SVG");
            let mut paths = vec![];
            for node in document.descendants().filter(|n| n.is_element()) {
                let a = |s| {
                    node.attribute(s)
                        .unwrap_or("0")
                        .parse::<f32>()
                        .unwrap_or(0.0)
                };
                let d = match node.tag_name().name() {
                    "path" => node.attribute("d").unwrap_or("").to_owned(),
                    "circle" => {
                        let (x, y, r) = (a("cx"), a("cy"), a("r"));
                        format!(
                            "M{} {} a{r} {r} 0 1 0 {} 0 a{r} {r} 0 1 0 {} 0",
                            x - r,
                            y,
                            2.0 * r,
                            -2.0 * r
                        )
                    }
                    "line" => format!("M{} {} L{} {}", a("x1"), a("y1"), a("x2"), a("y2")),
                    "polyline" | "polygon" => {
                        let nums: Vec<_> = node
                            .attribute("points")
                            .unwrap_or("")
                            .split([',', ' '])
                            .filter(|s| !s.is_empty())
                            .collect();
                        let mut d = String::new();
                        for (i, pair) in nums.as_chunks::<2>().0.iter().enumerate() {
                            d += &format!(
                                "{}{} {} ",
                                if i == 0 { "M" } else { "L" },
                                pair[0],
                                pair[1]
                            );
                        }
                        if node.tag_name().name() == "polygon" {
                            d.push('Z');
                        }
                        d
                    }
                    "rect" => {
                        let (x, y, w, h) = (a("x"), a("y"), a("width"), a("height"));
                        format!("M{x} {y} h{w} v{h} h{} Z", -w)
                    }
                    _ => continue,
                };
                if let Some(path) = sk::Path::from_svg(d) {
                    paths.push(path);
                }
            }
            icons.insert(name, paths);
        }
        Self {
            fonts,
            paragraphs: HashMap::new(),
            faces: HashMap::new(),
            icons,
        }
    }
    // Explicit paint parameters keep the reference typography visible at call sites.
    #[allow(clippy::too_many_arguments)]
    fn paragraph(
        &self,
        text: &str,
        width: f32,
        size: f32,
        weight: i32,
        color: Color,
        center: bool,
        italic: bool,
    ) -> Paragraph {
        let mut ps = ParagraphStyle::new();
        if center {
            ps.set_text_align(sk::textlayout::TextAlign::Center);
        }
        let mut style = TextStyle::new();
        let family = if text.chars().any(|c| ('\u{0400}'..='\u{04ff}').contains(&c)) {
            "Roboto"
        } else {
            "Outfit"
        };
        style
            .set_font_families(&[family, "Roboto"])
            .set_font_size(size)
            .set_color(color)
            .set_height(1.4);
        style.set_font_style(sk::FontStyle::new(
            sk::font_style::Weight::from(weight),
            sk::font_style::Width::NORMAL,
            if italic {
                sk::font_style::Slant::Italic
            } else {
                sk::font_style::Slant::Upright
            },
        ));
        let coords = [sk::font_arguments::variation_position::Coordinate {
            axis: sk::FourByteTag::from_chars('w', 'g', 'h', 't'),
            value: weight as f32,
        }];
        let args = sk::FontArguments::new().set_variation_design_position(
            sk::font_arguments::VariationPosition {
                coordinates: &coords,
            },
        );
        if family == "Outfit" {
            style.set_font_arguments(&args);
        }
        let mut b = ParagraphBuilder::new(&ps, self.fonts.clone());
        b.push_style(&style);
        b.add_text(text);
        let mut p = b.build();
        p.layout(width);
        p
    }
    #[allow(clippy::too_many_arguments)]
    fn text(
        &mut self,
        c: &Canvas,
        text: &str,
        r: Rect,
        size: f32,
        weight: i32,
        color: Color,
        center: bool,
    ) -> f32 {
        let key = format!("{text}|{}|{size}|{weight}|{:?}|{center}", r.width(), color);
        if !self.paragraphs.contains_key(&key) {
            if self.paragraphs.len() > 512 {
                self.paragraphs.clear();
            }
            let p = self.paragraph(text, r.width(), size, weight, color, center, false);
            self.paragraphs.insert(key.clone(), p);
        }
        let p = &self.paragraphs[&key];
        p.paint(c, (r.left, r.top));
        p.height()
    }
    pub fn icon(&self, c: &Canvas, name: &str, x: f32, y: f32, size: f32, color: Color) {
        let Some(paths) = self.icons.get(name) else {
            return;
        };
        c.save();
        c.translate((x, y));
        c.scale((size / 24.0, size / 24.0));
        let mut p = paint(color);
        p.set_style(sk::paint::Style::Stroke)
            .set_stroke_width(2.0)
            .set_stroke_cap(sk::paint::Cap::Round)
            .set_stroke_join(sk::paint::Join::Round);
        for path in paths {
            c.draw_path(path, &p);
        }
        c.restore();
    }
    fn glass(c: &Canvas, r: Rect, radius: f32, polished: bool, blur: f32) {
        let rr = RRect::new_rect_xy(r, radius, radius);
        c.save();
        c.clip_rrect(rr, None, true);
        if blur > 0.0
            && let Some(filter) = sk::image_filters::blur((blur, blur), TileMode::Clamp, None, None)
        {
            c.save_layer(
                &sk::canvas::SaveLayerRec::default()
                    .bounds(&r)
                    .backdrop(&filter),
            );
            c.restore();
        }
        let colors = if polished {
            vec![
                rgba(255, 255, 255, 13),
                rgba(0, 0, 0, 38),
                rgba(0, 0, 0, 140),
            ]
        } else {
            vec![rgba(255, 255, 255, 8), rgba(255, 255, 255, 5)]
        };
        let shader = linear(((r.left, r.top), (r.right, r.bottom)), colors.as_slice());
        let mut p = paint(WHITE);
        p.set_shader(shader);
        c.draw_rect(r, &p);
        if polished {
            let sheen = [
                rgba(255, 255, 255, 0),
                rgba(255, 255, 255, 18),
                rgba(255, 255, 255, 0),
            ];
            p.set_shader(linear(
                ((r.left, r.top), (r.right, r.top + r.height() * 0.35)),
                sheen.as_slice(),
            ));
            c.draw_rect(r, &p);
        }
        c.restore();
        let mut edge = paint(rgba(255, 255, 255, if polished { 80 } else { 43 }));
        edge.set_style(sk::paint::Style::Stroke)
            .set_stroke_width(1.0);
        c.draw_rrect(rr, &edge);
    }
    fn face(&mut self, index: usize, back: bool, width: f32) -> Picture {
        let key = (index, back, width.to_bits());
        if let Some(p) = self.faces.get(&key) {
            return p.clone();
        }
        let word = WORDS[index];
        let mut recorder = PictureRecorder::new();
        let c = recorder.begin_recording(rect(0.0, 0.0, width, 280.0), false);
        Self::glass(c, rect(0.0, 0.0, width, 280.0), 24.0, false, 0.0);
        if !back {
            self.icon(c, "edit", width - 38.0, 22.0, 18.0, MUTED);
        }
        let title = if back { word.translation } else { word.german };
        let mut size = if back { 25.6 } else { 28.8 };
        let mut title_p = self.paragraph(title, width - 48.0, size, 700, WHITE, true, false);
        while title_p.height() > 80.0 && size > 18.0 {
            size -= 1.0;
            title_p = self.paragraph(title, width - 48.0, size, 700, WHITE, true, false);
        }
        title_p.paint(
            c,
            (
                24.0,
                if back {
                    (280.0 - title_p.height()) / 2.0
                } else {
                    48.0
                },
            ),
        );
        if !back && !word.forms.is_empty() {
            let p = self.paragraph(word.forms, width - 48.0, 12.0, 400, MUTED, true, true);
            p.paint(c, (24.0, 91.0));
        }
        if !back {
            // Measure the full body, then fit it once into the fixed 280px face.
            let mut size = 14.0;
            loop {
                let total: f32 = word
                    .examples
                    .iter()
                    .map(|s| {
                        self.paragraph(s, width - 76.0, size, 400, MUTED, false, false)
                            .height()
                            + 18.0
                    })
                    .sum();
                if total <= 143.0 || size <= 10.5 {
                    break;
                }
                size -= 0.5;
            }
            let mut y = 123.0;
            for example in word.examples {
                let p = self.paragraph(
                    &format!("· {example}"),
                    width - 76.0,
                    size,
                    400,
                    MUTED,
                    false,
                    false,
                );
                let h = p.height() + 14.0;
                round(
                    c,
                    rect(30.0, y, width - 60.0, h),
                    7.0,
                    rgba(255, 255, 255, 5),
                );
                let mut border = paint(rgba(255, 255, 255, 230));
                border
                    .set_stroke_width(2.5)
                    .set_stroke_cap(sk::paint::Cap::Round);
                c.draw_line((30.5, y + 6.0), (30.5, y + h - 6.0), &border);
                p.paint(c, (39.0, y + 7.0));
                y += h + 6.0;
            }
        }
        let picture = recorder.finish_recording_as_picture(None).unwrap();
        if self.faces.len() > 16 {
            self.faces.clear();
        }
        self.faces.insert(key, picture.clone());
        picture
    }
    fn background(c: &Canvas, w: f32, h: f32) {
        c.clear(Color::BLACK);
        let colors = [rgba(21, 19, 34, 200), rgba(7, 6, 12, 0)];
        let mut p = paint(WHITE);
        p.set_shader(sk::gradient_shader::radial(
            (w * 0.48, h * 0.95),
            h * 0.55,
            colors.as_slice(),
            None,
            TileMode::Clamp,
            None,
            None,
        ));
        c.draw_rect(rect(0.0, 0.0, w, h), &p);
    }
    fn prepare_faces(&mut self, index: usize, width: f32) {
        // Shape both sides and the next card before a gesture starts. A frame at
        // the 90-degree crossing must only replay cached drawing commands.
        for i in index..=(index + 1).min(WORDS.len() - 1) {
            for back in [false, true] {
                self.face(i, back, width);
            }
        }
    }
    pub fn draw(&mut self, c: &Canvas, w: f32, h: f32, s: &Session, now: Instant) {
        Self::background(c, w, h);
        let layout = Layout::new(w, h);
        if s.finished {
            self.summary(c, w, h, s);
            return;
        }
        if !s.motion.active(now) {
            self.prepare_faces(s.index, layout.card.width());
        }
        // First spike includes a working local study scene. Other tabs stay on this
        // scene until their real functionality is ported (not a fake live account).
        for (x, name) in [(12.0, "back"), (60.0, "volume"), (w - 52.0, "settings")] {
            Self::glass(c, rect(x, 12.0, 40.0, 40.0), 10.0, false, 0.0);
            self.icon(c, name, x + 10.0, 22.0, 20.0, MUTED);
        }
        self.text(
            c,
            "Ein gutes Omen",
            rect(108.0, 21.0, w - 230.0, 30.0),
            16.0,
            700,
            WHITE,
            true,
        );
        self.icon(c, "star", w - 119.0, 25.0, 15.0, MUTED);
        self.text(
            c,
            "0",
            rect(w - 100.0, 23.0, 12.0, 25.0),
            12.0,
            700,
            WHITE,
            true,
        );
        let secs = now.saturating_duration_since(s.started).as_secs();
        round(
            c,
            rect(w - 85.0, 23.0, 28.0, 19.0),
            5.0,
            rgba(255, 255, 255, 25),
        );
        self.text(
            c,
            &format!("{}:{:02}", secs / 60, secs % 60),
            rect(w - 85.0, 24.0, 28.0, 18.0),
            10.0,
            700,
            WHITE,
            true,
        );
        let bw = (w - 48.0) / 3.0;
        for (i, (value, name)) in [
            ("3".to_owned(), "Всего слов"),
            ((WORDS.len() - s.ratings.len()).to_string(), "К повторению"),
            (s.ratings.len().to_string(), "Пройдено сегодня"),
        ]
        .iter()
        .enumerate()
        {
            let x = 12.0 + i as f32 * (bw + 12.0);
            Self::glass(c, rect(x, 68.0, bw, 76.0), 12.0, false, 0.0);
            self.text(
                c,
                value,
                rect(x + 6.0, 80.0, bw - 12.0, 26.0),
                18.0,
                700,
                WHITE,
                true,
            );
            self.text(
                c,
                name,
                rect(x + 6.0, 109.0, bw - 12.0, 32.0),
                11.2,
                400,
                MUTED,
                true,
            );
        }
        let t = s.motion.value(now);
        let back = t >= 0.5;
        let theta = t * std::f32::consts::PI + if back { std::f32::consts::PI } else { 0.0 };
        if theta.cos().abs() > 0.002 {
            let face = self.face(s.visible_word(now), back, layout.card.width());
            c.save();
            let cx = w / 2.0;
            let cy = layout.card.center_y();
            c.translate((cx, cy));
            let matrix = sk::Matrix::new_all(
                theta.cos(),
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
                theta.sin() / PERSPECTIVE,
                0.0,
                1.0,
            );
            c.concat(&matrix);
            c.translate((-layout.card.width() / 2.0, -140.0));
            c.draw_picture(&face, None, None);
            c.restore();
        }
        for (i, r) in layout.ratings.iter().enumerate() {
            Self::glass(c, *r, 16.0, false, 0.0);
            let mut edge = paint(rgba(255, 255, 255, 210));
            edge.set_style(sk::paint::Style::Stroke)
                .set_stroke_width(1.0);
            c.draw_rrect(RRect::new_rect_xy(*r, 16.0, 16.0), &edge);
            let labels = [
                "Не помню",
                "С трудом",
                "Частично",
                "Почти",
                "Помню",
                "Отлично",
            ];
            let intervals = ["1 час", "1 день", "2 дня", "4 дня", "7 дней", "17 дней"];
            let y = r.center_y() - 19.0;
            self.text(
                c,
                labels[i],
                rect(r.left + 4.0, y, r.width() - 8.0, 24.0),
                15.2,
                600,
                WHITE,
                true,
            );
            self.text(
                c,
                intervals[i],
                rect(r.left + 4.0, y + 24.0, r.width() - 8.0, 18.0),
                12.0,
                400,
                WHITE,
                true,
            );
            if i >= 4 {
                self.icon(c, "star", r.right - 20.0, r.top + 7.0, 11.0, MUTED);
            }
        }
        let r = layout.widget;
        Self::glass(c, r, 20.0, true, 14.0);
        for i in 0..7 {
            round(
                c,
                rect(
                    r.left + 25.0 + i as f32 * 7.0,
                    r.top + 32.0 - i as f32 * 3.0,
                    4.5,
                    9.0 + i as f32 * 3.0,
                ),
                2.0,
                if i < 3 {
                    rgba(183, 203, 224, 235)
                } else {
                    rgba(255, 255, 255, 25)
                },
            );
        }
        self.icon(
            c,
            "star",
            w / 2.0 - 10.0,
            r.top + 18.0,
            20.0,
            rgba(205, 188, 235, 255),
        );
        for i in 0..8 {
            let mut p = paint(rgba(
                255,
                255,
                255,
                if i < s.ratings.len() { 170 } else { 40 },
            ));
            p.set_style(sk::paint::Style::Stroke).set_stroke_width(1.3);
            c.draw_circle(
                (
                    w - 100.0 + (i % 4) as f32 * 12.0,
                    r.top + 23.0 + (i / 4) as f32 * 12.0,
                ),
                3.2,
                &p,
            );
        }
        round(
            c,
            rect(r.left + 16.0, r.bottom - 16.0, r.width() - 80.0, 3.0),
            2.0,
            rgba(255, 255, 255, 25),
        );
        round(
            c,
            rect(
                r.left + 16.0,
                r.bottom - 16.0,
                (r.width() - 80.0) * s.ratings.len() as f32 / WORDS.len() as f32,
                3.0,
            ),
            2.0,
            rgba(183, 203, 224, 240),
        );
        self.text(
            c,
            &format!("{} / {}", WORDS.len() - s.ratings.len(), WORDS.len()),
            rect(r.right - 57.0, r.bottom - 25.0, 48.0, 22.0),
            11.0,
            700,
            MUTED,
            true,
        );
        self.navigation(c, &layout);
        if s.settings {
            self.settings(c, w, h, s);
        }
    }
    fn navigation(&self, c: &Canvas, l: &Layout) {
        Self::glass(c, l.nav, 99.0, true, 20.0);
        let bw = l.nav.width() / 5.0;
        round(
            c,
            rect(
                l.nav.left + 2.0 * bw + 1.0,
                l.nav.top + 4.0,
                bw - 2.0,
                l.nav.height() - 8.0,
            ),
            99.0,
            WHITE,
        );
        for (i, name) in ["user", "book", "play", "upload", "settings"]
            .iter()
            .enumerate()
        {
            self.icon(
                c,
                name,
                l.nav.left + (i as f32 + 0.5) * bw - 10.0,
                l.nav.center_y() - 10.0,
                20.0,
                if i == 2 {
                    Color::BLACK
                } else {
                    rgba(255, 255, 255, 190)
                },
            );
        }
    }
    fn summary(&mut self, c: &Canvas, w: f32, h: f32, s: &Session) {
        self.icon(
            c,
            "star",
            w / 2.0 - 16.0,
            60.0,
            32.0,
            rgba(170, 210, 192, 255),
        );
        self.text(
            c,
            "Сессия завершена",
            rect(20.0, 120.0, w - 40.0, 45.0),
            28.0,
            700,
            WHITE,
            true,
        );
        self.text(
            c,
            "Ein gutes Omen",
            rect(20.0, 166.0, w - 40.0, 30.0),
            14.0,
            400,
            MUTED,
            true,
        );
        Self::glass(c, rect(20.0, 220.0, w - 40.0, 96.0), 20.0, false, 0.0);
        self.text(
            c,
            "3 карточки",
            rect(30.0, 245.0, w - 60.0, 40.0),
            24.0,
            700,
            WHITE,
            true,
        );
        for i in 0..6 {
            let count = s.ratings.iter().filter(|(_, r)| *r == i + 1).count();
            let y = 360.0 + i as f32 * 36.0;
            self.text(
                c,
                [
                    "Не помню",
                    "С трудом",
                    "Частично",
                    "Почти",
                    "Помню",
                    "Отлично",
                ][i as usize],
                rect(24.0, y, 110.0, 28.0),
                13.0,
                400,
                MUTED,
                false,
            );
            round(
                c,
                rect(140.0, y + 7.0, w - 190.0, 5.0),
                3.0,
                rgba(255, 255, 255, 20),
            );
            round(
                c,
                rect(140.0, y + 7.0, (w - 190.0) * count as f32 / 3.0, 5.0),
                3.0,
                rgba(183, 203, 224, 220),
            );
        }
        round(c, rect(20.0, h - 90.0, w - 40.0, 48.0), 99.0, WHITE);
        self.text(
            c,
            "К обучению",
            rect(20.0, h - 77.0, w - 40.0, 30.0),
            14.0,
            700,
            Color::BLACK,
            true,
        );
    }
    fn settings(&mut self, c: &Canvas, w: f32, h: f32, s: &Session) {
        round(c, rect(0.0, 0.0, w, h), 0.0, rgba(0, 0, 0, 150));
        Self::glass(c, rect(12.0, 80.0, w - 24.0, h - 160.0), 24.0, true, 20.0);
        self.text(
            c,
            "Настройки карточек",
            rect(32.0, 110.0, w - 64.0, 40.0),
            23.0,
            700,
            WHITE,
            false,
        );
        for (i, (name, on)) in [
            ("Сначала перевод", s.first_back),
            ("Уменьшить движение", s.reduced),
        ]
        .iter()
        .enumerate()
        {
            let y = 180.0 + i as f32 * 70.0;
            self.text(
                c,
                name,
                rect(32.0, y, w - 125.0, 40.0),
                15.0,
                500,
                WHITE,
                false,
            );
            round(
                c,
                rect(w - 78.0, y, 40.0, 24.0),
                12.0,
                if *on { WHITE } else { rgba(255, 255, 255, 40) },
            );
            round(
                c,
                rect(w - 76.0 + if *on { 16.0 } else { 0.0 }, y + 2.0, 20.0, 20.0),
                10.0,
                if *on { Color::BLACK } else { WHITE },
            );
        }
        self.text(
            c,
            "Закрыть",
            rect(32.0, h - 140.0, w - 64.0, 35.0),
            15.0,
            700,
            WHITE,
            true,
        );
    }
}

pub fn capture(directory: &str) -> Result<(), Box<dyn std::error::Error>> {
    std::fs::create_dir_all(directory)?;
    let mut renderer = Renderer::new();
    let now = Instant::now();
    let mut s = Session::new(now);
    let animation = std::env::args().any(|a| a == "--animation");
    let samples: Vec<(String, u64)> = if animation {
        (0..=66)
            .map(|i| (format!("frame-{i:03}"), i * 33))
            .collect()
    } else {
        [
            ("front", 0),
            ("flip-150", 150),
            ("flip-300", 300),
            ("back", 600),
            ("next-150", 1150),
            ("next-front", 1600),
        ]
        .into_iter()
        .map(|(name, time)| (name.to_owned(), time))
        .collect()
    };
    for (name, time) in samples {
        if animation {
            if time == 330 {
                s.flip(now + Duration::from_millis(time));
            }
            if time == 1287 {
                s.rate(5, now + Duration::from_millis(time));
            }
        } else {
            if time == 150 {
                s.flip(now);
            }
            if time == 1150 {
                s.rate(5, now + Duration::from_millis(1000));
            }
        }
        let mut surface = sk::surfaces::raster_n32_premul((390, 844)).ok_or("raster surface")?;
        renderer.draw(
            surface.canvas(),
            390.0,
            844.0,
            &s,
            now + Duration::from_millis(time),
        );
        let image = surface.image_snapshot();
        let data = image
            .encode(None, sk::EncodedImageFormat::PNG, None)
            .ok_or("PNG encode")?;
        std::fs::write(
            Path::new(directory).join(format!("cometa-{name}.png")),
            data.as_bytes(),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pixel_layout_has_no_empty_band() {
        let l = Layout::new(411.43, 891.43);
        assert!((l.widget.top - l.ratings[5].bottom - 12.0).abs() < 0.001);
        assert_eq!(l.card.height(), 280.0);
    }
    #[test]
    fn glass_blurs_the_backdrop_instead_of_only_tinting_it() {
        let sample = |blur| {
            let mut surface = sk::surfaces::raster_n32_premul((80, 40)).unwrap();
            let c = surface.canvas();
            c.clear(Color::BLACK);
            c.draw_rect(rect(0.0, 0.0, 40.0, 40.0), &paint(WHITE));
            Renderer::glass(c, rect(8.0, 4.0, 64.0, 32.0), 6.0, true, blur);
            surface.peek_pixels().unwrap().get_color((36, 20)).r() as i32
        };
        assert!(
            sample(0.0) - sample(8.0) > 20,
            "glass must sample and blur neighboring backdrop pixels"
        );
    }
}
