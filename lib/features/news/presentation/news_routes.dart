const newsPath = '/news';

/// The channel scrolled to post [id] (a tapped `type=news` push).
String newsPostPath(Object id) => '$newsPath?post=$id';

/// The channel's name: `texts.news_title` when the dashboard sets it.
const newsDefaultTitle = 'الأخبار';
