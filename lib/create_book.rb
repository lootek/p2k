require 'json'
require 'fileutils'
require 'open-uri'
require 'open_uri_redirections'
# require 'kindlerb'
# require '/mnt/data/projects/kindlerb.github/lib/kindlerb.rb'
require 'nokogiri'
require 'uri'

module CreateBook

	# Create book files
	def self.create_files(article, pocket_username, parse_engine)
		puts article.inspect

		added_time = DateTime.strptime(article['time_added'], '%s')

		str_id = pocket_username + '_' + added_time.strftime('%Y-%m-%d_%H-%M-%S') + '_' + article['resolved_id']
		article_root = ::Rails.root.join('public', 'generated', str_id, parse_engine)

		mobi_filename  	= article_root.to_s + '/' + str_id + '_' + parse_engine + '.mobi'
		article_filename 	= article_root.to_s + '/' + str_id + '_' + parse_engine + '.html'

		images_dir = article_root.join('img')
		FileUtils.mkdir_p(images_dir)

		cover_img = ''

		# Create HTML files for the articles
		File.open(article_filename, "w") do |f|

			if parse_engine == "pocket"
				article_html = self.parse_pocket(article['resolved_url'])
			elsif parse_engine == "readability"
				article_html = self.parse_readability(article['resolved_url'])
			end

			article_html, main_img = self.find_and_download_images(article_html, images_dir)

			cover_img = main_img

			f.write("<html>" +
				"<head>" +
					'<meta http-equiv="Content-Type" content="text/html; charset=utf-8">' +
					"<title>" + article['given_title'] + "</title>" +
				"</head>" +
				"<body>" +
					"<h1>" + article['resolved_title'] + "</h1>" +
					"<header>" + article['excerpt'] + "</header>" +
					"<article>" +
						article_html.html_safe +
					"</article>" +
				"</body>" +
				"</html>"
			)
		end

		article_uri = URI(article['resolved_url'])

		command = "ebook-convert " + article_filename + " " + mobi_filename +
					" --output-profile kindle" +
					" --prefer-metadata-cover" +
					" --title '" + article['resolved_title'] + "'" +
					" --pubdate '" + added_time.strftime("%d-%m-%Y") + "'" +
					" --publisher '" + article_uri.host + "'" +
					" --authors '" + article_uri.host + "'"
					" --tags '" + article_uri.host + "," + "pocket" + "'"

		if not cover_img.blank?
			command = command + " --cover '" + cover_img + "'"
		end

		# Return the path to the book
		return article_root, command, mobi_filename
	end

	# Parse the articles via Pocket Article API (Private Beta)
	def self.parse_pocket(url)
		begin
			response = RestClient.get 'https://text.getpocket.com/v3/text', {
				:params => {
					:url => url,
					:consumer_key => Settings.POCKET_CONSUMER_KEY,
					:images => 1,
					# :refresh => 1,
					:output => "json"
				}
			}

		rescue => e
			mesg = "Pocket Article View API failed: " + e.message + "! Switching to Readability... (" + url + ")\n"

			Rails.logger.debug mesg
			return mesg
		end

		parsed = JSON.parse(response)
		return parsed['article']
	end

	# Parse the articles via Readability API
	def self.parse_readability(url)
		begin
			response = RestClient.get 'https://readability.com/api/content/v1/parser', {
				:params => {
					:url => url,
					:token => Settings.READABILITY_PARSER_KEY
				}
			}

		rescue => e
			mesg = "Readability API failed on URL: " + url + " with error: " + e.message + "\n"

			Rails.logger.debug mesg
			return mesg
		end

		parsed = JSON.parse(response)
		return parsed['content']
	end

	# Parse the articles via Diffbot API
	# def self.parse_diffbot(url)
	# 	begin
	# 		response = RestClient.get 'https://api.diffbot.com/v3/article', {:params => {
	# 			:url => url, :token => Settings.DIFFBOT_API_KEY
	# 			}}
	# 	rescue => e
	# 		Rails.logger.debug "Diffbot API failed! Switching to Readability...\n"
	# 		return self.parse_readability(url, e.message)
	# 	end
	# 	parsed = JSON.parse(response)

	# 	# If there is an error in the response, switch to Readability API
	# 	if parsed['error']
	# 		return self.parse_readability(url, parsed['error'])
	# 	else
	# 		return parsed['objects'][0]['html']
	# 	end
	# end

	# Find, download and replace paths of images in the created book to enable local access
	def self.find_and_download_images(html, save_to)

		cover_img = ''

		# Find all images in a given HTML
		Nokogiri::HTML(html).xpath("//img/@src").each do |src|
			begin
				src = src.to_s
				# Make image name SHA1 hash (only alphanumeric chars) and its extension .jpg
				img_hexname = Digest::SHA1.hexdigest(src)

				image_name = img_hexname + '.jpg'
				converted_image_name = img_hexname + '_converted.jpg'
				cover_image_name = img_hexname + '_cover.jpg'

				image_filename = save_to.join(image_name).to_s
				converted_image_filename = save_to.join(image_name).to_s
				cover_image_filename = save_to.join(image_name).to_s

				# Download image
				open(image_filename, 'wb') do |file|
					image_from_src = open(src, :allow_redirections => :safe).read
					file << image_from_src
				end

				# convert "$img" -compose over -background white -flatten -resize "640x640>" -alpha off -colorspace Gray "conv_$img"
				command = 'convert ' + image_filename + ' -compose over -background white -flatten -resize "640x640>" -alpha off -colorspace Gray ' + converted_image_filename
				created = system command
				Rails.logger.debug "imagick convert result: " + created.inspect

				if cover_img.blank?
					cover_img = cover_image_filename

					# convert "conv_$img" -background gray -gravity center -extent 400x640 "cover_$img"
					command = 'convert ' + converted_image_filename + ' -background gray -gravity center -extent 400x640 ' + cover_image_filename
					created = system command
					Rails.logger.debug "imagick convert result: " + created.inspect
				end

				# Replace the image URL with downloaded local version
				html = html.gsub(src, "img/" + converted_image_filename)
			rescue => e
				# If the image URL cannot be fetched, print an error message
				puts "IMAGE CANNOT BE DOWNLOADED!: " + e.message + "\n Image URL: " + src
				next
			end
		end

		# Return the new html
		return html, cover_img
	end

end