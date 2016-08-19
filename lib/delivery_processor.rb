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

		attachments ||= []

		articles.each do |article|
			article_root, command, mobi_filename = CreateBook.create_files(article[1], delivery.user.username)

			# article_root = '/mnt/data/projects/p2k.github/public/generated/080520162318_lootek'

			# Create the ebook
			Dir.chdir(article_root)

			# created = Kindlerb.run(article_root, true)
			# Rails.logger.debug "Kindlerb result: " + created.inspect
			# Rails.logger.debug created

			Rails.logger.debug "ebook-convert command: " + command.inspect
			created = system command
			Rails.logger.debug "ebook-convert result: " + created.inspect
			Rails.logger.debug created

			# If the system call returns anything other than nil, the call was successful
			successful = $?.exitstatus.nil? ? false : true

			# Email the ebook
			if successful
				Rails.logger.debug "Kindle file created successfully!\n"
				art_attachment = mobi_filename
				attachments.push(art_attachment)
			else
				Rails.logger.debug "Error: Kindle file could not be created!\n"
			end

			# Delete the ebook
			# FileUtils.rm_rf(article_root)
		end

		PocketMailer.delivery_email(delivery, attachments, articles).deliver_now

		delivery_log = "----------------\n" +
					   "Delivery processed!\n" +
					   "Recipient: " + delivery.user.username + "\n" +
					   "Kindle Email: " + delivery.kindle_email + "\n" +
					   "Delivery created at " + Time.now.to_s + "\n" +
					   "----------------\n"
		Rails.logger.debug delivery_log

	end

end
