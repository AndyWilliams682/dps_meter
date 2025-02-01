use std::collections::HashMap;
use std::time::SystemTime;

use image::DynamicImage;
use opencv::core::Rect;
use rusty_tesseract::Args;
use xcap::Window;
use xcap::image::{GenericImage, ImageBuffer, Rgb, GrayImage};
use opencv::{
    core::{bitwise_and, bitwise_not, copy_make_border, in_range, Mat, MatTraitConst, Point_, Scalar, BORDER_CONSTANT},
    imgproc::{bounding_rect, cvt_color, get_structuring_element, morphology_default_border_value, morphology_ex, COLOR_BGR2HSV, INTER_NEAREST, MORPH_DILATE, MORPH_OPEN, MORPH_RECT},
    prelude::MatTraitConstManual,
};


const TEXT_MIN: Scalar = Scalar::new(0.0, 0.0, 104.0, 0.0);
const TEXT_MAX: Scalar = Scalar::new(165.0, 13.0, 255.0, 0.0);


fn capture_region(
    x: u32,
    y: u32,
    width: u32,
    height: u32
) -> Result<ImageBuffer<Rgb<u8>, Vec<u8>>, xcap::XCapError> {
    let windows = Window::all()?;

    // TODO: Pick a specific window?
    for window in windows {
        if window.title() == "Path of Exile 2" && !window.is_minimized() {
            let image = window
                .capture_image()?
                .sub_image(x, y, width, height)
                .to_image();
            return Ok(DynamicImage::ImageRgba8(image).into_rgb8())
        }
    }
    return Err(xcap::XCapError::new("Path of Exile 2 is either not open, or minimized".to_string()))
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
        2.0,
        2.0,
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
    let my_args = Args {
        //model language (tesseract default = 'eng')
        //available languages can be found by running 'rusty_tesseract::get_tesseract_langs()'
        lang: "eng".to_string(),
    
        //map of config variables
        //this example shows a whitelist for the normal alphabet. Multiple arguments are allowed.
        //available arguments can be found by running 'rusty_tesseract::get_tesseract_config_parameters()'
        config_variables: HashMap::from([(
                "tessedit_char_whitelist".into(),
                "0123456789,".into(),
            )]),
        dpi: Some(150),       // specify DPI for input image
        psm: Some(6),         // define page segmentation mode 6 (i.e. "Assume a single uniform block of text")
        oem: Some(3),         // define optical character recognition mode 3 (i.e. "Default, based on what is available")
    };

    let raw_ocr = rusty_tesseract::image_to_string(
        &rusty_tesseract::Image::from_dynamic_image(&mask).unwrap(),
        &my_args
    )
        .unwrap();

    let output = raw_ocr.trim().replace(",", "").parse::<u32>()?;

    return Ok(output)
}


fn read_damage(region: Rect) -> Result<u32, anyhow::Error> {
    let screenshot_result = capture_region(
        region.x as u32,
        region.y as u32,
        region.width as u32,
        region.height as u32
    );

    let screenshot = match screenshot_result {
        Ok(s) => s,
        Err(error) => panic!("Path of Exile 2 does not appear to be open or is minimzed. Reason: {error}")
    };

    let mask_result = get_mask(screenshot);

    let mask = match mask_result {
        Ok(s) => s,
        Err(error) => panic!("OpenCV was unable to process this screenshot. Reason: {error}")
    };

    let damage_result = read_mask(mask);

    match damage_result {
        Ok(s) => return Ok(s),
        Err(_) => return Ok(0)
    }
}
