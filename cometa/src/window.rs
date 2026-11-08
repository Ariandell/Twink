use crate::{
    model::Session,
    render::{Layout, Renderer},
};
use glutin::{
    config::{ConfigTemplateBuilder, GlConfig},
    context::{ContextApi, ContextAttributesBuilder, PossiblyCurrentContext},
    display::{GetGlDisplay, GlDisplay},
    prelude::{GlSurface, NotCurrentGlContext},
    surface::{Surface as GlSurfaceType, SurfaceAttributesBuilder, SwapInterval, WindowSurface},
};
use raw_window_handle::HasWindowHandle;
use skia_safe::Contains;
use skia_safe::{
    self as sk, ColorType, Surface,
    gpu::{self, SurfaceOrigin, gl::FramebufferInfo},
};
use std::{
    ffi::CString,
    num::NonZeroU32,
    time::{Duration, Instant},
};
use winit::{
    application::ApplicationHandler,
    dpi::LogicalSize,
    event::{ElementState, MouseButton, TouchPhase, WindowEvent},
    event_loop::{ActiveEventLoop, ControlFlow, EventLoop},
    keyboard::{Key, NamedKey},
    window::{Window, WindowId},
};

type Error = Box<dyn std::error::Error>;
struct GpuWindow {
    surface: Surface,
    gl_surface: GlSurfaceType<WindowSurface>,
    gr: gpu::DirectContext,
    context: PossiblyCurrentContext,
    window: Window,
    fb: FramebufferInfo,
    samples: usize,
    stencil: usize,
}
impl Drop for GpuWindow {
    fn drop(&mut self) {
        self.gr.release_resources_and_abandon();
    }
}
impl GpuWindow {
    fn new(event_loop: &ActiveEventLoop) -> Result<Self, Error> {
        let attrs = Window::default_attributes()
            .with_title("German · Cometa")
            .with_inner_size(LogicalSize::new(390.0, 844.0))
            .with_min_inner_size(LogicalSize::new(320.0, 760.0));
        let template = ConfigTemplateBuilder::new()
            .with_alpha_size(8)
            .with_stencil_size(8);
        let (window, config) = glutin_winit::DisplayBuilder::new()
            .with_window_attributes(Some(attrs))
            .build(event_loop, template, |configs| {
                configs.min_by_key(|c| c.num_samples()).expect("GL config")
            })?;
        let window = window.ok_or("No native window")?;
        let raw = window.window_handle()?.as_raw();
        let display = config.display();
        let attributes = ContextAttributesBuilder::new().build(Some(raw));
        let fallback = ContextAttributesBuilder::new()
            .with_context_api(ContextApi::Gles(None))
            .build(Some(raw));
        let context = unsafe {
            display
                .create_context(&config, &attributes)
                .or_else(|_| display.create_context(&config, &fallback))?
        };
        let size = window.inner_size();
        let attrs = SurfaceAttributesBuilder::<WindowSurface>::new().build(
            raw,
            NonZeroU32::new(size.width.max(1)).unwrap(),
            NonZeroU32::new(size.height.max(1)).unwrap(),
        );
        let gl_surface = unsafe { display.create_window_surface(&config, &attrs)? };
        let context = context.make_current(&gl_surface)?;
        gl::load_with(|s| display.get_proc_address(CString::new(s).unwrap().as_c_str()));
        let interface = gpu::gl::Interface::new_load_with(|name| {
            if name == "eglGetCurrentDisplay" {
                return std::ptr::null();
            }
            display.get_proc_address(CString::new(name).unwrap().as_c_str())
        })
        .ok_or("Skia OpenGL interface")?;
        let mut gr = gpu::direct_contexts::make_gl(interface, None).ok_or("Skia GPU context")?;
        let mut fbo = 0;
        unsafe {
            gl::GetIntegerv(gl::FRAMEBUFFER_BINDING, &mut fbo);
        }
        let fb = FramebufferInfo {
            fboid: fbo as u32,
            format: gpu::gl::Format::RGBA8.into(),
            ..Default::default()
        };
        let samples = config.num_samples() as usize;
        let stencil = config.stencil_size() as usize;
        let surface = Self::wrap(size.width, size.height, fb, &mut gr, samples, stencil)?;
        gl_surface.set_swap_interval(&context, SwapInterval::Wait(NonZeroU32::new(1).unwrap()))?;
        Ok(Self {
            surface,
            gl_surface,
            gr,
            context,
            window,
            fb,
            samples,
            stencil,
        })
    }
    fn wrap(
        w: u32,
        h: u32,
        fb: FramebufferInfo,
        gr: &mut gpu::DirectContext,
        samples: usize,
        stencil: usize,
    ) -> Result<Surface, Error> {
        let target = gpu::backend_render_targets::make_gl(
            (w.max(1) as i32, h.max(1) as i32),
            samples,
            stencil,
            fb,
        );
        gpu::surfaces::wrap_backend_render_target(
            gr,
            &target,
            SurfaceOrigin::BottomLeft,
            ColorType::RGBA8888,
            None,
            None,
        )
        .ok_or("GPU surface".into())
    }
    fn resize(&mut self, w: u32, h: u32) -> Result<(), Error> {
        self.gl_surface.resize(
            &self.context,
            NonZeroU32::new(w.max(1)).unwrap(),
            NonZeroU32::new(h.max(1)).unwrap(),
        );
        self.surface = Self::wrap(w, h, self.fb, &mut self.gr, self.samples, self.stencil)?;
        Ok(())
    }
    fn logical(&self) -> (f32, f32) {
        let size = self.window.inner_size();
        let scale = self.window.scale_factor() as f32;
        (size.width as f32 / scale, size.height as f32 / scale)
    }
}

struct Application {
    gpu: Option<GpuWindow>,
    renderer: Option<Renderer>,
    session: Session,
    cursor: (f32, f32),
    down: Option<(f32, f32)>,
    started: Instant,
    first_present: Option<f64>,
    smoke: bool,
    frames: Vec<f64>,
    last_second: u64,
    occluded: bool,
    last_motion_value: f32,
}
impl Application {
    fn new(now: Instant) -> Self {
        Self {
            gpu: None,
            renderer: None,
            session: Session::new(now),
            cursor: (0.0, 0.0),
            down: None,
            started: now,
            first_present: None,
            smoke: std::env::args().any(|s| s == "--smoke"),
            frames: vec![],
            last_second: 0,
            occluded: false,
            last_motion_value: 0.0,
        }
    }
    fn click(&mut self, p: (f32, f32)) {
        let Some(g) = &self.gpu else {
            return;
        };
        let (w, h) = g.logical();
        let l = Layout::new(w, h);
        let now = Instant::now();
        let contains = |r: sk::Rect| r.contains(sk::Point::new(p.0, p.1));
        if self.session.finished {
            if p.1 > h - 110.0 {
                self.session.reset(now);
            }
            return;
        }
        if self.session.settings {
            if (170.0..220.0).contains(&p.1) {
                self.session.first_back = !self.session.first_back;
                self.session.motion.retarget(
                    if self.session.first_back { 1.0 } else { 0.0 },
                    now,
                    self.session.reduced,
                );
            } else if (240.0..290.0).contains(&p.1) {
                self.session.reduced = !self.session.reduced;
            } else if p.1 > h - 160.0 || p.1 < 80.0 {
                self.session.settings = false;
            }
            return;
        }
        if contains(l.card) {
            self.session.flip(now);
        } else if let Some(index) = l.ratings.iter().position(|r| contains(*r)) {
            self.session.rate(index as u8 + 1, now);
        } else if p.0 > w - 55.0 && p.1 < 60.0 {
            self.session.settings = true;
        } else if p.0 < 55.0 && p.1 < 60.0 {
            self.session.reset(now);
        } else if contains(l.nav) && p.0 > l.nav.right - l.nav.width() / 5.0 {
            self.session.settings = true;
        }
    }
    fn save_metrics(&mut self) {
        self.frames.sort_by(f64::total_cmp);
        let value = serde_json::json!({"platform":std::env::consts::OS,"build":"release", "scope":"native desktop graphics spike, local 3-word demo, from run() entry to first swap return; excludes OS loader, not Android TTID or full-app readiness",
            "rust_run_entry_to_first_swap_ms":self.first_present,"frame_prepare_cpu_median_ms":self.frames.get(self.frames.len()/2),"frames":self.frames.len()});
        println!("{}", serde_json::to_string_pretty(&value).unwrap());
        if let Some(path) =
            std::env::args().find_map(|s| s.strip_prefix("--metrics=").map(str::to_owned))
            && let Err(e) = std::fs::write(path, serde_json::to_vec_pretty(&value).unwrap())
        {
            eprintln!("Metrics: {e}");
        }
    }
}
impl ApplicationHandler for Application {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.gpu.is_none() {
            match GpuWindow::new(event_loop) {
                Ok(g) => {
                    self.gpu = Some(g);
                    self.renderer = Some(Renderer::new());
                }
                Err(e) => {
                    eprintln!("Graphics initialization: {e}");
                    event_loop.exit();
                    return;
                }
            }
        }
        if let Some(g) = &self.gpu {
            g.window.request_redraw();
        }
    }
    fn suspended(&mut self, _: &ActiveEventLoop) {
        self.renderer = None;
        self.gpu = None;
    }
    fn about_to_wait(&mut self, event_loop: &ActiveEventLoop) {
        let Some(g) = &self.gpu else {
            event_loop.set_control_flow(ControlFlow::Wait);
            return;
        };
        if self.occluded || g.window.is_minimized().unwrap_or(false) {
            event_loop.set_control_flow(ControlFlow::Wait);
            return;
        }
        let now = Instant::now();
        let second = now
            .saturating_duration_since(self.session.started)
            .as_secs();
        if self.smoke
            || self.session.motion.active(now)
            || self.last_motion_value != self.session.motion.target
            || second != self.last_second
        {
            self.last_second = second;
            g.window.request_redraw();
        }
        event_loop.set_control_flow(ControlFlow::WaitUntil(
            now + Duration::from_millis(if self.smoke || self.session.motion.active(now) {
                16
            } else {
                1000
            }),
        ));
    }
    fn window_event(&mut self, event_loop: &ActiveEventLoop, _: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => event_loop.exit(),
            WindowEvent::Occluded(v) => {
                self.occluded = v;
                if !v && let Some(g) = &self.gpu {
                    g.window.request_redraw();
                }
            }
            WindowEvent::Resized(size) => {
                if let Some(g) = &mut self.gpu {
                    if let Err(e) = g.resize(size.width, size.height) {
                        eprintln!("Resize: {e}");
                        event_loop.exit();
                    } else {
                        g.window.request_redraw();
                    }
                }
            }
            WindowEvent::CursorMoved { position, .. } => {
                if let Some(g) = &self.gpu {
                    let scale = g.window.scale_factor() as f32;
                    self.cursor = (position.x as f32 / scale, position.y as f32 / scale);
                }
            }
            WindowEvent::MouseInput {
                state,
                button: MouseButton::Left,
                ..
            } => {
                if state == ElementState::Pressed {
                    self.down = Some(self.cursor);
                } else if let Some(start) = self.down.take()
                    && (self.cursor.0 - start.0).hypot(self.cursor.1 - start.1) < 12.0
                {
                    self.click(self.cursor);
                }
                if let Some(g) = &self.gpu {
                    g.window.request_redraw();
                }
            }
            WindowEvent::Touch(t) => {
                if let Some(g) = &self.gpu {
                    let scale = g.window.scale_factor() as f32;
                    let p = (t.location.x as f32 / scale, t.location.y as f32 / scale);
                    match t.phase {
                        TouchPhase::Started => self.down = Some(p),
                        TouchPhase::Ended => {
                            if let Some(start) = self.down.take()
                                && (p.0 - start.0).hypot(p.1 - start.1) < 12.0
                            {
                                self.click(p);
                            }
                        }
                        TouchPhase::Cancelled => self.down = None,
                        _ => {}
                    }
                    if let Some(g) = &self.gpu {
                        g.window.request_redraw();
                    }
                }
            }
            WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed => {
                let now = Instant::now();
                match event.logical_key {
                    Key::Named(NamedKey::Space) => self.session.flip(now),
                    Key::Named(NamedKey::Escape) => {
                        if self.session.settings {
                            self.session.settings = false;
                        } else {
                            event_loop.exit();
                        }
                    }
                    Key::Character(s) => {
                        if let Ok(n) = s.parse::<u8>() {
                            self.session.rate(n, now);
                        }
                    }
                    _ => {}
                }
                if let Some(g) = &self.gpu {
                    g.window.request_redraw();
                }
            }
            WindowEvent::RedrawRequested => {
                let Some(g) = &mut self.gpu else {
                    return;
                };
                let Some(renderer) = &mut self.renderer else {
                    return;
                };
                if self.occluded {
                    return;
                }
                let now = Instant::now();
                if self.smoke && self.first_present.is_some() && !self.session.motion.active(now) {
                    if self.session.motion.target == 0.0 {
                        self.session.flip(now);
                    } else {
                        self.session.rate(5, now);
                    }
                }
                let (w, h) = g.logical();
                let c = g.surface.canvas();
                c.save();
                let scale = g.window.scale_factor() as f32;
                c.scale((scale, scale));
                let prepare = Instant::now();
                renderer.draw(c, w, h, &self.session, now);
                self.last_motion_value = self.session.motion.value(now);
                c.restore();
                if self.smoke {
                    self.frames.push(prepare.elapsed().as_secs_f64() * 1000.0);
                }
                if let Err(e) = g.gr.flush_and_submit() {
                    eprintln!("GPU flush: {e:?}");
                    event_loop.exit();
                    return;
                }
                if let Err(e) = g.gl_surface.swap_buffers(&g.context) {
                    eprintln!("Present: {e}");
                    event_loop.exit();
                    return;
                }
                if self.first_present.is_none() {
                    self.first_present = Some(self.started.elapsed().as_secs_f64() * 1000.0);
                }
                if self.smoke && self.started.elapsed() > Duration::from_secs(3) {
                    self.save_metrics();
                    event_loop.exit();
                }
            }
            _ => {}
        }
    }
}
pub fn run() -> Result<(), Error> {
    let started = Instant::now();
    let event_loop = EventLoop::new()?;
    event_loop.run_app(&mut Application::new(started))?;
    Ok(())
}
#[cfg(target_os = "android")]
pub fn run_android(app: android_activity::AndroidApp) -> Result<(), Error> {
    let started = Instant::now();
    use winit::platform::android::EventLoopBuilderExtAndroid;
    let event_loop = EventLoop::builder().with_android_app(app).build()?;
    event_loop.run_app(&mut Application::new(started))?;
    Ok(())
}
