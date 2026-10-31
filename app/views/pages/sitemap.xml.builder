xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  @paths.each do |path|
    xml.url do
      xml.loc "#{SeoHelper::SITE_URL}#{path}"
    end
  end
end
