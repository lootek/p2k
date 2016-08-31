require 'fileutils'
# require 'kindlerb'
# require '/mnt/data/projects/kindlerb.github/lib/kindlerb.rb'

include DeliveryOptions
include CreateBook

module DeliveryProcessor

	# Check if there are any deliveries to be processed
	def self.check
		Rails.logger.debug "DELIVERY CHECKED at " + Time.now.to_s + "\n"
		Delivery.all.each do |d|
			time = Time.now.in_time_zone(d.time_zone)
			# If delivery is daily only look for matching hours, otherwise check days as well
			if d.frequency == 'daily'
				if time.hour == d.hour
					self.deliver d
				end
			else # weekly
				if time.hour == d.hour and time.wday == Delivery.days[d.day]
					self.deliver d
				end
			end
		end
	end

	# Process deliveries from start to beginning
	def self.deliver(delivery)

		# Fetch articles based on delivery option i.e. list, timed, random
		articles = DeliveryOptions.method(delivery.option).call(delivery.user.access_token, delivery.count, delivery.archive_delivered)

		# Create file tree from Pocket articles

		mail_attachments ||= []
		mail_articles ||= []

		articles.each do |article|

			# Create the ebook from article parsed using readability
			article_root, command, mobi_filename = CreateBook.create_files(article[1], delivery.user.username, "readability")
			Rails.logger.debug("readability parse result: " + (!article_root ? "false" : article_root.to_s) + ", " + command + ", " + (!mobi_filename ? "false" : mobi_filename.to_s))
			if article_root != false
				Dir.chdir(article_root)
				Rails.logger.debug "ebook-convert command: " + command.inspect
				created = system command
				Rails.logger.debug "ebook-convert result: " + created.inspect
			end

			# Create the ebook from article parsed using pocket
			article_root, command, mobi_filename = CreateBook.create_files(article[1], delivery.user.username, "pocket")
			Rails.logger.debug("pocket parse result: " + (!article_root ? "false" : article_root.to_s) + ", " + command + ", " + (!mobi_filename ? "false" : mobi_filename.to_s))
			if article_root != false
				Dir.chdir(article_root)
				Rails.logger.debug "ebook-convert command: " + command.inspect
				created = system command
				Rails.logger.debug "ebook-convert result: " + created.inspect
			end

			# If the system call returns anything other than nil, the call was successful
			successful = $?.exitstatus.nil? ? false : true

			if article_root == false
				Rails.logger.info "Already processed, skipping..."
				next
			end

			if successful
				Rails.logger.debug "Kindle file created successfully!\n"
				art_attachment = mobi_filename
				mail_attachments.push(art_attachment)
			else
				Rails.logger.debug "Error: Kindle file could not be created!\n"
			end

			mail_articles.push(article[1])

			# Email ebooks in packs of 25
			if mail_attachments.length == 25
				PocketMailer.delivery_email(delivery, mail_attachments, mail_articles).deliver_now

				delivery_log = "Recipient: " + delivery.user.username + "\n" +
							   	"Kindle Email: " + delivery.kindle_email + "\n" +
							   	"Delivery created at " + Time.now.to_s + "\n"
				Rails.logger.debug delivery_log

				mail_attachments.clear
				mail_articles.clear
			end

		end

		# Email the remaining ebooks (if any)
		if mail_attachments.length > 0
			PocketMailer.delivery_email(delivery, mail_attachments, mail_articles).deliver_now

			delivery_log = "Recipient: " + delivery.user.username + "\n" +
						   	"Kindle Email: " + delivery.kindle_email + "\n" +
						   	"Delivery created at " + Time.now.to_s + "\n"
			Rails.logger.debug delivery_log
		end

	end

end
