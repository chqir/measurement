require 'RMagick'
require 'rubyXL'
include Magick

#set it up so each image gets a ractor

#SETTINGS
$top_left_crop = 330           # where is the top left corner of the cropped center
$crop = 300                    # size of the cropped image
$black_threshold = 20          # black values below this will be considered the center
$white_threshold = 120         # white values about this will be considered to be spots
$pixels_per_mm = 13.714        # how many pixels equal one mm: image center is 7mm across, or 100 pixels across. 100/7 = 14.286
$spots_size = 3                # how many pixels should make up the smaller spots
$center_size = 5000            # how many pixels should make up the center
$margin = 3.5                  # distance of edge of target from center (mm)
$eightorfive = 5               # if its working on an 8 or 5 directory

#SPREADHSHEET SETUP
$spreadsheet_path = "/Users/cm/Documents/projects/programming/measurement/main/working.xlsx"
$workbook = RubyXL::Parser.parse($spreadsheet_path)
$worksheet = $workbook['5'] #this is VERY computationally expensive

def average_coordinates(array)
  array = array.transpose
  x = array[0].inject{ |sum, el| sum + el }.to_f / array[0].size
  y = array[1].inject{ |sum, el| sum + el }.to_f / array[1].size
  return [x, y]
end

def generate_black_and_white_array(image_object, are_spots_white)
  black_and_white_array = Array.new(image_object.rows) { Array.new(image_object.columns) { nil } }

  if are_spots_white == true
    image_object.each_pixel {|pixel, column, row| pixel.red / 257 >= $white_threshold ? black_and_white_array[row][column] = 1 : black_and_white_array[row][column] = nil}
  elsif are_spots_white == false
    image_object.each_pixel {|pixel, column, row| pixel.red / 257 <= $black_threshold ? black_and_white_array[row][column] = 1 : black_and_white_array[row][column] = nil}
  end

  return black_and_white_array
end

def dfs(x,y, groups, width, height, groups_found)
  if x == width || x == 0 || y == height || y == 0 || groups[x][y] != 1 || groups_found.length > 8000
    return groups_found
  end

  groups_found << [x,y]
  groups[x][y] = 0

  dfs(x - 1, y, groups, width, height, groups_found)
  dfs(x + 1, y, groups, width, height, groups_found)
  dfs(x, y - 1, groups, width, height, groups_found)
  dfs(x, y + 1, groups, width, height, groups_found)
end

def find_spots(working_array)
  spots_array = []
  spots = []

  islands = 0

  working_array.each_with_index do |row, x|
    row.each_with_index do |item, y|
      if item == 1
        #spots <<
        islands += 1
        spots_array << dfs(x, y, working_array, working_array[0].count, working_array.count, [])
        #spots = []
      end
    end
  end

  return spots_array
end

# @action:
def populate_sheet(workbook, worksheet, data_array, image_number, study_id)
  #make this loop through all rows
  #worksheet.add_cell(3, 0, study_id)

  first_empty = nil

  for i in 2..100 do
    if worksheet[i][0].value == nil || worksheet[i][0].value == study_id
      first_empty = i
      break
    end
  end

  if first_empty == nil
    puts "smtn messed up w populate"
    return false
  end

  #workbook, worksheet, data_array, image_number, study_id

  worksheet.add_cell(i, 0, study_id)
  #((image_number - 1) * 10) + 2 ======== the first cell of a new image


  data_array.each_with_index do |item, index|
    current_row = (((image_number - 1) * 10) + 2) + index
    worksheet.add_cell(i, current_row, item.to_s)
  end

  workbook.write($spreadsheet_path)
end

# @returns: a array of the distances from the center in mm
def handle_image(image_path)
  working_image = ImageList.new(image_path)

  image_center = working_image.excerpt($top_left_crop, $top_left_crop, $crop, $crop)

  spots_array  = find_spots(generate_black_and_white_array(working_image, true))
  center_array = find_spots(generate_black_and_white_array(image_center, false))

  filtered_spots  = spots_array.reject {|island| island.count < $spots_size}
  filtered_center = center_array.reject {|island| island.count < $center_size}.sort_by(&:length).reverse #should sort most amount in ar => least


  spot_coordinates = []
  filtered_spots.each {|spot_ar| spot_coordinates << average_coordinates(spot_ar)}

  if filtered_center[0] == nil
    return false
  end

  center_coordinates = [average_coordinates(filtered_center[0])[0] + $top_left_crop, average_coordinates(filtered_center[0])[1] + $top_left_crop]

  spot_distances = []
  spot_coordinates.each do |spot_ar|
    spot_distances << (Math.sqrt((center_coordinates[0] - spot_ar[0])**2 + (center_coordinates[1] - spot_ar[1])**2) / 14.286).round(1)
  end

  number_of_times_hit = spot_distances.count {|spot| spot <= $margin } #this is the number of times it hit target

  #if number_of_times_hit > 1
  #  return false
  #end

  spot_distances = spot_distances.map {|spot| spot = (spot - $margin).round(1)}.sort.reverse
  spot_distances = spot_distances.map{|item| [0, item].max}

  return spot_distances
end

# @returns: an array of image paths in a given directory
def get_paths_in_dir(directory_path, study_id)
  fixed_paths = []
  $eightorfive.times{ fixed_paths << []}

  Dir.glob(directory_path + '/*.png') do |file_path|
    fixed_paths[file_path[-7].to_i - 1] << file_path
  end

  fixed_paths = fixed_paths.map {|sub_ar| sub_ar.reverse!}.flatten

  return fixed_paths
end

def handle_directory(directory_path)
  study_id = directory_path[-6..-1]

  get_paths_in_dir(directory_path, study_id).each_with_index do |path, index|
    raw_data = handle_image(path)

    if raw_data == false || raw_data.length > 10
      puts "failed on " + path
      File.open('/Users/cm/Documents/projects/programming/measurement/main/failures.txt', 'a') { |f|
        f.puts ("failed on " + directory_path + "/"+ path + "\n")
      }
      next
    end
    #print path + "\n"
    #print raw_data
    populate_sheet($workbook, $worksheet, raw_data, index + 1, study_id)
    #puts "\n"
  end
end

def handle_full(directory_path)
  Dir.chdir(directory_path)
  Dir.glob('*').select {|f| File.directory? f}.each_with_index do |sub_dir_path, index|
    puts sub_dir_path.to_s
    puts ((100.0 / 67.0) * index + 1).round(2).to_s + "% complete"
    handle_directory(sub_dir_path)
  end
end

handle_full("/Users/cm/Documents/projects/programming/measurement/photos-testing/5-STRIP")
#print handle_image("/Users/cm/Documents/projects/programming/measurement/photos-testing/8-STRIP/017330/017330-2-1.png")
