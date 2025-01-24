use xcap::Window;
use xcap::image::{GenericImage, ImageBuffer, Rgba, SubImage};
use std::thread::sleep;
use std::time::Duration;


fn capture_region(
    x: u32,
    y: u32,
    width: u32,
    height: u32
) -> Result<ImageBuffer<Rgba<u8>, Vec<u8>>, String> {
    let windows = Window::all().unwrap();

    // TODO: Pick a specific window?
    for window in windows {
        if window.title() == "Path of Exile 2" && !window.is_minimized() {
            let image = window
                .capture_image()
                .unwrap()
                .sub_image(x, y, width, height)
                .to_image();
            return Ok(image)
        }
    }
    return Err("Path of Exile 2 is either not open, or minimized".to_string())
}


fn main() {
    // TODO: Find the good x/y/w/h values for testing
    sleep(Duration::from_secs(5));
    let y = 0;
    let x = (1920.0 * 0.3) as u32;
    let height = (1080.0 * 0.05) as u32;
    let width = (1920.0 * 0.4) as u32;
    let test_image: Result<ImageBuffer<Rgba<u8>, Vec<u8>>, String> = capture_region(x, y, width, height);
    match test_image {
        Ok(i) => i.save("test.png").unwrap(),
        Err(e) => println!("{:?}", e),
    }
}



