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
		Rails.logger.debug article.inspect

		if not article['resolved_id']
			Rails.logger.debug "============================ ERROR/SKIPPING ============================"
			return false, "", false
		end

		added_time = DateTime.strptime(article['time_added'], '%s')

		str_id = pocket_username + '_' + added_time.strftime('%Y-%m-%d_%H-%M-%S') + '_' + article['resolved_id']
		article_root = ::Rails.root.join('public', 'generated', str_id, parse_engine)

		mobi_filename  	= article_root.to_s + '/' + str_id + '_' + parse_engine + '.mobi'
		article_filename 	= article_root.to_s + '/' + str_id + '_' + parse_engine + '.html'

		images_dir = article_root.join('img')

		if Dir.exist?(images_dir)
			return false, "", false
		end

		FileUtils.mkdir_p(images_dir)

		cover_img = ''

		article_url = article['resolved_url']
		if not article_url
			article_url = article['given_url']
		end

		article_title = article['resolved_title']
		if not article_title
			article_title = article['given_title']
		end

		# Create HTML files for the articles
		File.open(article_filename, "w") do |f|

			if parse_engine == "pocket"
				article_html = self.parse_pocket(article_url)
			end

			if article_html.empty?
				next
			end

			article_html, main_img = self.find_and_download_images(article_html, images_dir)

			cover_img = main_img

			f.write("<html>" +
				"<head>" +
					'<meta http-equiv="Content-Type" content="text/html; charset=utf-8">' +
					"<title>" + article_title + "</title>" +
				"</head>" +
				"<body>" +

					"<header>" +
						"<h1>" + article_title + "</h1>" +
					 	"<h2><a href=\"" + article_url + "\" target=\"_blank\">" + article_url + "</a></h2>" +
					"</header>" +

					"<section>" +
						article['excerpt'] +
					"</section>" +

					"<article>" +
						article_html.html_safe +
					"</article>" +

				"</body>" +
				"</html>"
			)
		end

		article_uri = URI(article_url)

		command = "ebook-convert " + article_filename + " " + mobi_filename +
					" --output-profile kindle" +
					" --prefer-metadata-cover" +
					" --title '" + article_title + "'" +
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
			mesg = "Pocket Article View API failed: " + e.message + "\n"

			Rails.logger.debug mesg
			return mesg
		end

		parsed = JSON.parse(response)
		return parsed['article']
	end

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