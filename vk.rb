require 'httparty'
require 'json'

module DiscordBot
	module VK
	  class VK
		include HTTParty

		def initialize( client )
			@client = client
			@bot = client.bot
			@channels = client.channels
			@config = client.config
		end

		def start_group_gathering
			Thread.new {
				@config[ 'groups' ].each do |k, v|
					do_new_thread( k )
					sleep 5
				end

				sleep @config[ 'vk_refresh' ]
				start_group_gathering
			}
		end

		def do_new_thread( t )
			Thread.new {
				begin
					get_data_from_group( t )
				rescue => err
					puts err
				end
			}
		end

		def get_data_from_group( g )
			r =  JSON.parse(
				HTTParty.get(
					"https://api.vk.com/method/wall.get?owner_id=#{ g }&count=1&offset=1&extended=1",
					:verify => false
				).body,
				:symbolize_names => true
			)[ :response ]
			resp = r[ :wall ][ 1 ]

			if @config[ 'groups' ][ g ] == resp[ :id ] then
				return true
			end

			emb = Discordrb::Webhooks::Embed.new

			emb.color = "#507299"
			emb.author = Discordrb::Webhooks::EmbedAuthor.new( name: 'AppleJuicetice', url: 'https://github.com/Kopcap94/Discord-AJ', icon_url: 'http://images3.wikia.nocookie.net/siegenax/ru/images/2/2c/CM.png' )
			emb.title = r[ :groups ][ 0 ][ :name ]
			emb.description = "http://vk.com/wall#{ g }_#{ resp[ :id ] }"
			emb.thumbnail = Discordrb::Webhooks::EmbedThumbnail.new( url: "#{ r[ :groups ][ 0 ][ :photo_big ] }" )

			text = resp[ :text ].gsub( "<br>", "\n" ).gsub( /#[^\s]+([\s\n]*)?/, "" )
			if text != "" then 
				emb.add_field( name: "Текст поста:", value: text )
			end

			attach = resp[ :attachments ]
			if !attach.nil? then
				attach = attach[ 0 ]

				case attach[ :type ]
				when "photo"
					p = attach[ :photo ][ :src_big ] 

					emb.add_field( name: "Изображение", value: p )
					emb.image = Discordrb::Webhooks::EmbedImage.new( url: p )
				when "video"
					p = attach[ :video ]

					emb.add_field( name: "Видео", value: "http://vk.com/video#{ g }_#{ p[ :id ] }" )
					emb.add_field( name: "Название", value: p[ :title ] )
					emb.image = Discordrb::Webhooks::EmbedImage.new( url: p[ :image_big ] ) 
				when "doc"
					p = attach[ :doc ]

					emb.add_field( name: "Документ", value: p[ :url ] )
					emb.add_field( name: "Название", value: p[ :title ] )
				end
			end

			@bot.send_message( @channels[ 'news' ], '', false, emb )

			@config[ 'groups' ][ g ] = resp[ :id ]
			@client.save_config
		end
	  end
	end
end