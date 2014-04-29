require 'RMagick'
require 'barby'
require 'barby/barcode/code_128'
require 'barby/barcode/code_39'
require 'barby/outputter/rmagick_outputter'

class MagickBurger < Magick::Image

  def initialize(width, height, options = {})
    @dpi = (options[:dpi] || 300)
    background_color = (options[:background] || '#FFFFFF')
    background_color = "##{background_color}" unless background_color.first == '#'
    super(*rationalize(width, height)) {self.background_color = background_color}
    @background_color = background_color
    @x_offset, @y_offset = 0, 0
    self.y_resolution = self.x_resolution = @dpi
  end

  def offset x, y
    return x + @x_offset, y + @y_offset
  end

  def middle_width
    unrationalize(columns / 2.0)
  end

  def middle_height
    unrationalize(columns)
  end

  def add_offset x, y
    @x_offset += rationalize x
    @y_offset += rationalize y
  end

  def set_offset x, y
    @x_offset, @y_offset = rationalize x, y
  end

  def rationalize *args
    if args.length == 1
      (args.first * @dpi / 25.400).to_i
    else
      args.collect {|x| (x * @dpi / 25.400).to_i }
    end
  end

  def convert_to_rgb
    if colorspace == Magick::CMYKColorspace
      strip!
      add_profile("#{Rails.root}/lib/assets/USWebUncoated.icc")
      colorspace == Magick::SRGBColorspace
      add_profile("#{Rails.root}/lib/assets/sRGB_no_scaling.icc")
    end
    raise 'This colorspace is not supported.' unless [Magick::RGBColorspace, Magick::SRGBColorspace].member? colorspace
  end

  def unrationalize *args
    if args.length == 1
      args.first *  25.400 / @dpi
    else
      args.collect {|x| x * 25.400 / @dpi }
    end
  end

  def font_rationalize height
    ((height * @dpi - 1) / 18.19).to_i + 1
  end

  def readable_color background_color = @background_color
    r_layer = background_color[0..1]
    v_layer = background_color[2..3]
    b_layer = background_color[4..5]
    sum = r_layer.to_i(16) + v_layer.to_i(16) + v_layer.to_i(16)
    lightness = sum / 3
    return '#FFFFFF' if lightness < 130
    '#000000'
  end

  def resize
    super.resize!
  end

  def add_picture picture, dim_hash, x, y, options = {}
    width = dim_hash[:width]
    height = dim_hash[:height]
    x, y = rationalize x, y
    x, y = offset x, y
    if picture.is_a? String
      picture = Magick::ImageList.new(picture).first
    end
    if width
      width = rationalize width
      ratio = width / picture.columns.to_f
    elsif height
      height = rationalize height
      ratio = height / picture.rows.to_f
    else
      raise 'No dimension given'
    end
    picture.resize!(ratio)
    case options[:align]
    when :center
      x = x - (picture.columns / 2)
    else
    end
    result = unrationalize x + picture.columns, y + picture.rows
    sharped_picture = picture.unsharp_mask
    picture.destroy!
    composite!(sharped_picture, x, y, Magick::OverCompositeOp)
    sharped_picture.destroy!
    result
  end

  def add_barcode_image barcode_value, xmin, height, x, y, *options
    options = options.first || {}
    xmin, height, x, y = rationalize xmin, height, x, y
    x, y = offset x, y
    max_width = rationalize options[:max_width] if options[:max_width]
    barbycode = case options[:code]
    when :b
      Barby::Code128B.new(barcode_value)
    when :c
      Barby::Code128C.new(barcode_value)
    when :code_39
      Barby::Code39.new(barcode_value)
    when :code_128c
      Barby::Code128C.new(barcode_value)
    when :code_128b
      Barby::Code128B.new(barcode_value)
    when :code_128a
      Barby::Code128A.new(barcode_value)
    else
      Barby::Code128A.new(barcode_value)
    end
    barby_img = Barby::RmagickOutputter.new(barbycode).to_image(xdim: xmin, height: height)
    barby_img.resize!(max_width, height) if max_width && max_width < barby_img.columns
    composite!(barby_img, x - (barby_img.columns/2), y, Magick::OverCompositeOp)
    barby_width, barby_height = unrationalize barby_img.columns, barby_img.rows
    barby_img.destroy!
    return barby_width, barby_height
  end

  def add_vertical_text x, y, text, fontsize, invert = false, *options
    x, y = rationalize x, y
    x, y = offset x, y
    text_color = "#000000"
    p = Magick::Draw.new
    p.pointsize = font_rationalize fontsize
    p.align = Magick::LeftAlign
    p.font_family = 'Helvetica'
    p.stroke = 'transparent'
    metrics = p.get_type_metrics(self, text)
    p.rotation = invert ? 270 : 90
    x = x - metrics[:height] unless invert
    p.annotate(self, 0, 0, x, y, text) {
      self.font_family = 'Helvetica'
      self.fill = text_color
    }
    unrationalize (x - @x_offset)
  end

  def add_condensed_text x, y, text, fontsize, width, *options
    options = options.first || {}
    x, y, width = rationalize x, y, width
    x, y = offset x, y
    p = Magick::Draw.new
    p.pointsize = font_rationalize fontsize
    p.stroke = 'transparent'
    p.font = "#{Rails.root}/lib/assets/monaco.ttf" if options[:font] == :monaco
    p.fill = "#000000"
    metrics = p.get_type_metrics(self, text)
    im = Magick::Image.new(metrics[:width], metrics[:ascent] - metrics[:descent]) {|i| i.background_color= "Transparent"}
    p.annotate(im, 0, 0, 0, metrics[:ascent], text)
    im.resize!(width,im.rows) if metrics[:width] > width
    new_x = case options[:align]
    when :center
      x - im.columns/2
    when :right
      x - im.columns
    else
      x
    end
    composite!(im, new_x, y, Magick::OverCompositeOp)
    unrationalize y + metrics[:height] - @y_offset
  end

  def add_text x, y, text, fontsize, *options
    options = options.first || {}
    x,y = rationalize x,y
    x, y = offset x, y
    text_color = readable_color
    p = Magick::Draw.new
    p.pointsize = font_rationalize fontsize
    if options[:font] == :monaco
      p.font = "#{Rails.root}/lib/assets/monaco.ttf"
    else
      p.font_family = 'Helvetica'
    end
    p.fill = "#000000"
    p.align = case options[:align]
    when :center
      Magick::CenterAlign
    when :right
      Magick::RightAlign
    else
      Magick::LeftAlign
    end
    p.font_weight = case options[:font_weight]
    when :bold
      Magick::BoldWeight
    else
      Magick::NormalWeight
    end
    p.stroke = 'transparent'
    metrics = p.get_type_metrics(self, text)
    p.annotate(self, 0, 0, x, y + metrics[:height], text) {
      self.fill = text_color
    }
    unrationalize (metrics[:height] + y - @y_offset)
  end

  def add_rect x1,y1,x2,y2, *options
    options = options.first || {}
    stroke_width = options[:stroke_width] || 0.2
    if options[:style] == :inner
      x1, y1, x2, y2 = x1 + stroke_width / 2.0, y1 + stroke_width / 2.0, x2 - stroke_width / 2.0, y2 - stroke_width / 2.0
    end

    x1, y1, x2, y2 = rationalize x1, y1, x2, y2
    x1, y1 = offset x1, y1
    x2, y2 = offset x2, y2
    p = Magick::Draw.new
    p.stroke('#000000')
    p.stroke_width(rationalize(stroke_width))
    p.stroke_dashoffset(rationalize(stroke_width))
    p.fill_opacity('0.0')
    p.stroke_opacity('1.0')
    p.rectangle(x1,y1,x2,y2)
    p.draw(self)
  end

  def add_line x1, y1, x2, y2, stroke_weight = 0.2
    x1, y1, x2, y2, stroke_weight = rationalize x1, y1, x2, y2, stroke_weight
    x1, y1 = offset x1, y1
    x2, y2 = offset x2, y2
    p = Magick::Draw.new
    p.stroke('#000000')
    p.stroke_width(stroke_weight)
    p.stroke_opacity('1.0')
    p.line(x1, y1, x2, y2)
    p.draw(self)
  end
end
