use image::DynamicImage;
use tesseract_static::tesseract::Tesseract;
use xcap::Window;
use xcap::image::{GenericImage, ImageBuffer, Rgb, GrayImage};
use opencv::{
    core::{bitwise_and, bitwise_not, copy_make_border, in_range, Mat, MatTraitConst, Point_, Scalar, BORDER_CONSTANT},
    imgproc::{bounding_rect, cvt_color, get_structuring_element, morphology_default_border_value, morphology_ex, COLOR_BGR2HSV, INTER_NEAREST, MORPH_DILATE, MORPH_OPEN, MORPH_RECT},
    prelude::MatTraitConstManual,
};
use log::{info, warn};
use flutter_logger;

flutter_logger::flutter_logger_init!();


const TEXT_MIN: Scalar = Scalar::new(0.0, 0.0, 104.0, 0.0);
const TEXT_MAX: Scalar = Scalar::new(165.0, 13.0, 255.0, 0.0);

const TRAINING_DATA: &[u8] = include_bytes!("./eng.traineddata");


fn capture_region(
    x: u32,
    y: u32,
    width: u32,
    height: u32
) -> Result<ImageBuffer<Rgb<u8>, Vec<u8>>, xcap::XCapError> {
    let windows = Window::all()?;

    // TODO: Pick a specific window instead of searching through all of them (may need to cache it somehow)
    for window in windows {
        if window.title()? == "Path of Exile 2" && !window.is_minimized()? {
            let image = window
                .capture_image()?
                .sub_image(x, y, width, height)
                .to_image();
            return Ok(DynamicImage::ImageRgba8(image).into_rgb8())
        }
    }
    return Err(xcap::XCapError::new("Path of Exile 2 is either not open, or minimized".to_string())) // TODO: Make error types
}


fn get_mask(screenshot: ImageBuffer<Rgb<u8>, Vec<u8>>) -> Result<DynamicImage, anyhow::Error> {
    let dims = screenshot.dimensions();
    let dims: (usize, usize, usize) = (dims.1 as usize, dims.0 as usize, 3);

    let screenshot = ndarray::Array3::from_shape_vec(dims, screenshot.to_vec())?;

    let int_dims: Vec<i32> = screenshot.shape().iter().map(|&sz| sz as i32).collect();

    let screenshot = screenshot.as_standard_layout();
    let screenshot = Mat::from_slice(screenshot.as_slice().unwrap())?;
    let screenshot = screenshot.reshape_nd(3, &[int_dims[0], int_dims[1]])?;
    
    let mut hsv = Mat::default();
    cvt_color(
        &screenshot,
        &mut hsv,
        COLOR_BGR2HSV,
        0,
        opencv::core::AlgorithmHint::ALGO_HINT_DEFAULT
    )?;

    let mut mask = Mat::default();
    in_range(&hsv, &TEXT_MIN, &TEXT_MAX, &mut mask)?;

    let kernel = get_structuring_element(
        MORPH_RECT,
        opencv::core::Size_::new(2, 2),
        Point_ { x: -1, y: -1 }
    )?;
    let mut opened = Mat::default();
    morphology_ex(
        &mask,
        &mut opened,
        MORPH_OPEN,
        &kernel,
        Point_ { x: -1, y: -1 },
        1,
        BORDER_CONSTANT,
        morphology_default_border_value()?
    )?;

    let kernel = get_structuring_element(
        MORPH_RECT,
        opencv::core::Size_::new(5, 3),
        Point_ { x: -1, y: -1 }
    )?;
    let mut dilated = Mat::default();
    morphology_ex(
        &opened,
        &mut dilated,
        MORPH_DILATE,
        &kernel,
        Point_ { x: -1, y: -1 },
        2,
        BORDER_CONSTANT,
        morphology_default_border_value()?
    )?;

    let mut roi = Mat::default();
    bitwise_and(&dilated, &mask, &mut roi, &opencv::core::no_array())?;

    let rect = bounding_rect(&roi)?;
    let roi = Mat::roi(&roi, rect)?;
    let mut inverted = Mat::default();
    bitwise_not(&roi, &mut inverted, &opencv::core::no_array())?;

    let mut with_border = Mat::default();
    copy_make_border(
        &inverted,
        &mut with_border,
        10,
        10,
        10,
        10,
        BORDER_CONSTANT,
        Scalar::from((255, 255, 255))
    )?;

    let mut result = Mat::default();
    opencv::imgproc::resize(
        &with_border,
        &mut result,
        opencv::core::Size_::new(0, 0),
        3.0,
        3.0,
        INTER_NEAREST
    )?;

    let new_dims = result.size()?;
    let new_w = new_dims.width as u32;
    let new_h = new_dims.height as u32;

    let result = ndarray::Array3::from_shape_vec(
        (new_h as usize, new_w as usize, 1),
        result
            .data_bytes()?
            .to_vec()
        )?;
    
    let result = DynamicImage::from(
        GrayImage::from_raw(new_w, new_h as u32, result.as_slice().unwrap().to_vec())
            .unwrap()
    );

    return Ok(result)
}


fn read_mask(mask: DynamicImage) -> Result<u32, anyhow::Error> {
    let tempfile = tempfile::Builder::new()
        .prefix("dps_meter")
        .suffix(".bmp")
        .rand_bytes(5)
        .tempfile()?;

    let path = tempfile.path();
    mask.save(path)?;

    // TODO: This shouldn't happen every single time (either check if it exists or do it once prior in the main func)
    let parent = std::env::temp_dir();
    std::fs::write(&parent.join("eng.traineddata"), &TRAINING_DATA[..])?;

    let raw_ocr = Tesseract::new(
            Some(&parent.display().to_string()),
            Some("eng"),
        )?
        .set_variable("tessedit_char_whitelist", "0123456789,")?
        .set_image(path.to_str().unwrap())?
        .get_text()?;

    let output = raw_ocr.trim().replace(",", "").parse::<u32>()?;

    return Ok(output)
}


pub fn read_damage(x: u32, y: u32, width: u32, height: u32) -> Result<u32, anyhow::Error> {
    info!("Capturing screenshot");
    let screenshot_result = capture_region(
        x,
        y,
        width,
        height
    );

    let screenshot = match screenshot_result {
        Ok(s) => {
            info!("Screenshot succesfully captured");
            s
        },
        Err(error) => return {
            warn!("{error}");
            Ok(0)
        }
    };

    let mask_result = get_mask(screenshot);

    let mask = match mask_result {
        Ok(s) => {
            info!("Mask successfully generated");
            s
        },
        Err(error) => return {
            warn!("OpenCV was unable to process this screenshot. Reason: {error}");
            Ok(0)
        }
    };

    let damage_result = read_mask(mask);

    match damage_result {
        Ok(s) => return {
            info!("Damage read: {s}");
            Ok(s)
        },
        Err(error) => return {
            warn!("Tesseract was unable to detect a number. Reason: {error}");
            Ok(0)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn open_test_image(path: &str) -> ImageBuffer<Rgb<u8>, Vec<u8>> {
        return image::ImageReader::open(path)
            .unwrap()
            .decode()
            .unwrap()
            .crop(576, 0, 1344, 65)
            .to_rgb8();
    }

    #[test]
    fn read_white_19950() {
        let image = open_test_image(r"tests\images\19950.jpg");
        let mask = get_mask(image).unwrap();
        let result = read_mask(mask).unwrap();
        assert_eq!(result, 19950);
    }

    #[test]
    fn read_white_55837() {
        let image = open_test_image(r"tests\images\55837.jpg");
        let mask = get_mask(image).unwrap();
        let result = read_mask(mask).unwrap();
        assert_eq!(result, 55837);
    }

    #[test]
    fn read_gray_203() {
        let image = open_test_image(r"tests\images\203.jpg");
        let mask = get_mask(image).unwrap();
        let result = read_mask(mask).unwrap();
        assert_eq!(result, 203);
    }

    #[test]
    #[should_panic]
    fn read_no_damage() {
        let image = open_test_image(r"tests\images\no_damage.jpg");
        let mask = get_mask(image).unwrap();
        read_mask(mask).unwrap(); // No number to read
    }
}
