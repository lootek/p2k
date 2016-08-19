require 'json'
require 'fileutils'
require 'open-uri'
require 'open_uri_redirections'
# require 'kindlerb'
# require '/mnt/data/projects/kindlerb.github/lib/kindlerb.rb'
require 'nokogiri'
require 'uri'

module CreateBook

	# Create book files necessary for kindlerb
	def self.create_files(article, username)
		puts article.inspect

		added_time = DateTime.strptime(article['time_added'], '%s')

		str_id = username + '_' + added_time.strftime('%Y-%m-%d_%H-%M-%S') + '_pocket_' + article['resolved_id']
		dir_name = str_id
		article_root = ::Rails.root.join('public', 'generated', dir_name)

		mobi_filename = article_root.to_s + '/' + str_id + '.mobi'
		article_filename = article_root.to_s + '/' + str_id + '.html'

		# Create folder for the book
		FileUtils.mkdir_p(article_root)

		# Create folder for the images
		images_dir = article_root.join('img')
		FileUtils.mkdir_p(images_dir)

		# Create folder for sections
		# sections = article_root.join('sections')
		# FileUtils.mkdir_p(sections)

		# Create folder for the only section: Home
		# articles_home = sections.join('000')
		# FileUtils.mkdir_p(articles_home)

		# Create _section.txt which contains the section title
		# _section = articles_home.join('_section.txt')
		# File.open(_section, "w+") do |f|
		# 	f.write("Home")
		# end

		#Create _document.yml
		# image = ::Rails.root.join('app', 'assets', 'images_dir', 'p2k-masthead.jpg')

		cover_img = ''

		# Create HTML files for the articles
		File.open(article_filename, "w") do |f|

			article_html = self.parse_pocket(article['resolved_url'])
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

		# _document = 'doc_uuid: pocket.' + article['resolved_id'] + "\n" +
		  # 	'title: "' + article['resolved_title'] + '"' + "\n" +
		  # 	'author: "' + article_uri.host + '"' + "\n" +
		  # 	'publisher: "' + article_uri.host + '"' + "\n" +
		  # 	'subject: "' + article['resolved_title'] + '"' + "\n" +
		  # 	'date: "' + Time.now.strftime("%d-%m-%Y") + '"' + "\n" +
		  # 	'masthead: "' + image.to_s + '"' + "\n" +
		  # 	'cover: "' + image.to_s + '"' + "\n" +
		  # 	'mobi_outfile: "' + mobi_filename + '"' + "\n"

		# document_path = article_root.join('_document.yml')
		# File.open(document_path, "w+") do |f|
		# 	f.write(_document)
		# end

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
			response = RestClient.get 'http://text.getpocket.com/v3/text', {:params => {
				:url => url, :consumer_key => Settings.POCKET_CONSUMER_KEY,
				:images => 1, :output => "json"
				}}
		rescue => e
			Rails.logger.debug "Pocket Article View API failed: " + e.message + "! Switching to Readability... (" + url + ")\n"

			return self.parse_readability(url, e.message)
		end
		parsed = JSON.parse(response)

		# If there is an error in the response, switch to Readability API
		if parsed['responseCode'] != "200"
			return self.parse_readability(url, parsed['excerpt'])
		else
			return parsed['article']
		end
	end

	# Parse the articles via Readability API
	def self.parse_readability(url, error)
		begin
			response = RestClient.get 'https://readability.com/api/content/v1/parser', {:params => {
				:url => url, :token => Settings.READABILITY_PARSER_KEY
				}}
		rescue => e
			Rails.logger.debug "Both APIs failed on URL: " + url + "\n"
			return "This article could not be fetched or is otherwise invalid.\n" +
				"This is most likely an issue with fetching the article from the source server.\n" +
				"URL: " + url + "\n" +
				"Parsing was first tried via Diffbot API. Error message:\n" + error + "\n" +
				"Parsing then tried via Readability API. Error message:\n" + e.message
		end
		parsed = JSON.parse(response)
		return parsed['content']
	end

	# Parse the articles via Diffbot API
	def self.parse_diffbot(url)
		begin
			response = RestClient.get 'https://api.diffbot.com/v3/article', {:params => {
				:url => url, :token => Settings.DIFFBOT_API_KEY
				}}
		rescue => e
			Rails.logger.debug "Diffbot API failed! Switching to Readability...\n"
			return self.parse_readability(url, e.message)
		end
		parsed = JSON.parse(response)

		# If there is an error in the response, switch to Readability API
		if parsed['error']
			return self.parse_readability(url, parsed['error'])
		else
			return parsed['objects'][0]['html']
		end
	end

	# Find, download and replace paths of images in the created book to enable local access
	def self.find_and_download_images(html, save_to)

		main_img = ''

		# Find all images in a given HTML
		Nokogiri::HTML(html).xpath("//img/@src").each do |src|
			begin
				src = src.to_s
				# Make image name SHA1 hash (only alphanumeric chars) and its extension .jpg
				image_name = Digest::SHA1.hexdigest(src) << '.jpg'

				# Download image
				image_url = save_to.join(image_name).to_s

				open(image_url, 'wb') do |file|
					image_from_src = open(src, :allow_redirections => :safe).read
					file << image_from_src
				end

				# Resize and make it greyscale
				# command = 'convert ' + image_url + ' -compose over -background white -flatten -resize "400x267>" -alpha off -colorspace Gray ' + image_url

				# convert "$img" -compose over -background white -flatten -resize "640x640>" -alpha off -colorspace Gray "conv_$img"
				command = 'convert ' + image_url + ' -compose over -background white -flatten -resize "640x640>" -alpha off -colorspace Gray ' + image_url
				created = system command
				Rails.logger.debug "imagick convert result: " + created.inspect

				if main_img.blank?
					main_img = image_url

					# convert "conv_$img" -background gray -gravity center -extent 400x640 "cover_$img"
					command = 'convert ' + image_url + ' -background gray -gravity center -extent 400x640 ' + image_url
					created = system command
					Rails.logger.debug "imagick convert result: " + created.inspect
				end

				# Replace the image URL with downloaded local version
				html = html.gsub(src, "img/" + image_name)
			rescue => e
				# If the image URL cannot be fetched, print an error message
				puts "IMAGE CANNOT BE DOWNLOADED!: " + e.message + "\n Image URL: " + src
				next
			end
		end

		# Return the new html
		return html, main_img
	end

end