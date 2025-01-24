use xcap::Window;


fn capture_region(
    x: u32,
    y: u32,
    w: u32,
    h: u32
) -> () {
    let windows = Window::all().unwrap();

    for window in windows {
        if window.app_name() == "Path of Exile 2" {
            println!(
                "Window: {:?} {:?} {:?}",
                window.title(),
                (window.x(), window.y(), window.width(), window.height()),
                (window.is_minimized(), window.is_maximized())
            );
        
            let image = window.capture_image().unwrap(); // TODO: Need to constrain to the region
            // return image // TODO: Figure out what type this should be
        }
    }
}
