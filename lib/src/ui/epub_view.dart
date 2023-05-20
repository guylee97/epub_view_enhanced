import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:epub_view_enhanced/src/custom_stack.dart';
import 'package:epub_view_enhanced/src/data/epub_cfi_reader.dart';
import 'package:epub_view_enhanced/src/data/epub_parser.dart';
import 'package:epub_view_enhanced/src/data/models/chapter.dart';
import 'package:epub_view_enhanced/src/data/models/chapter_view_value.dart';
import 'package:epub_view_enhanced/src/data/models/paragraph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:transparent_image/transparent_image.dart';
import 'package:http/http.dart' as http;
export 'package:epub_parser/epub_parser.dart';

part '../epub_controller.dart';
part '../helpers/epub_view_builders.dart';


const _minTrailingEdge = 0.55;
const _minLeadingEdge = -0.05;
const String uri="http://10.0.2.2:5000";

typedef ExternalLinkPressed = void Function(String href);

class EpubView extends StatefulWidget {
  const EpubView({
    required this.controller,
    this.onExternalLinkPressed,
    this.onChapterChanged,
    this.onDocumentLoaded,
    this.onDocumentError,
    this.onTapDown,
    this.onLongPress,
    this.builders = const EpubViewBuilders<DefaultBuilderOptions>(
      options: DefaultBuilderOptions(),
    ),
    this.shrinkWrap = false,
    required this.jsonBody,
    Key? key,
  }) : super(key: key);

  final EpubController controller;
  final ExternalLinkPressed? onExternalLinkPressed;
  final bool shrinkWrap;
  final void Function(EpubChapterViewValue? value)? onChapterChanged;
  final void Function(TapDownDetails details)? onTapDown;
  final void Function(BuildContext context, int index)? onLongPress;

  /// Called when a document is loaded
  final void Function(EpubBook document)? onDocumentLoaded;

  /// Called when a document loading error
  final void Function(Exception? error)? onDocumentError;

  /// Builders
  final EpubViewBuilders builders;

  //Json
  final String jsonBody;


  @override
  State<EpubView> createState() => _EpubViewState();
}

class _EpubViewState extends State<EpubView> {
  Exception? _loadingError;
  ItemScrollController? _itemScrollController;
  ItemPositionsListener? _itemPositionListener;
  List<EpubChapter> _chapters = [];
  List<Paragraph> _paragraphs = [];
  EpubCfiReader? _epubCfiReader;
  EpubChapterViewValue? _currentValue;
  final _chapterIndexes = <int>[];
  int highlightedPara = -1;
  int positionTemp=0;
  String? cfi;
  List<Data> listdatas = [];
  EpubController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    List<dynamic> parsedJson = jsonDecode(widget.jsonBody)["data"];
    for (int i = 0; i < parsedJson.length; i++) {
      listdatas.add(Data.fromJson(parsedJson[i]));
    }
    _itemScrollController = ItemScrollController();
    _itemPositionListener = ItemPositionsListener.create();
    _controller._attach(this);
    _controller.loadingState.addListener(() {
      switch (_controller.loadingState.value) {
        case EpubViewLoadingState.loading:
          break;
        case EpubViewLoadingState.success:
          widget.onDocumentLoaded?.call(_controller._document!);
          break;
        case EpubViewLoadingState.error:
          widget.onDocumentError?.call(_loadingError);
          break;
      }

      if (mounted) {
        setState(() {});
      }
    });
  }

  // @override
  // void dispose() {
  //   _itemPositionListener!.itemPositions.removeListener(_changeListener);
  //   _controller._detach();
  //   super.dispose();
  // }

  static Map<String, Widget?> imageMap = {};

  Future<bool> _init() async {
    if (_controller.isBookLoaded.value) {
      return true;
    }
    _chapters = parseChapters(_controller._document!);
    final parseParagraphsResult =
        parseParagraphs(_chapters, _controller._document!.Content);
    _paragraphs = parseParagraphsResult.flatParagraphs;
    _chapterIndexes.addAll(parseParagraphsResult.chapterIndexes);

    _epubCfiReader = EpubCfiReader.parser(
      cfiInput: _controller.epubCfi,
      chapters: _chapters,
      paragraphs: _paragraphs,
    );
    _itemPositionListener!.itemPositions.addListener(_changeListener);
    _controller.isBookLoaded.value = true;


    //Render images
    _controller._document?.Content?.Images?.forEach((key, value) {
      imageMap[key] = FadeInImage(
        fadeInDuration: const Duration(milliseconds: 250),
        fadeOutDuration: const Duration(milliseconds: 250),
        placeholder: MemoryImage(kTransparentImage),
        image: MemoryImage(Uint8List.fromList(value.Content!)),
      );
      // value.
    });

    return true;
  }

  Future<void> _changeListener() async {
    if (_paragraphs.isEmpty ||
        _itemPositionListener!.itemPositions.value.isEmpty) {
      return;
    }

    cfi=this._epubCfiReader?.generateCfi(
      book: _controller._document,
      chapter: this._currentValue?.chapter,
      paragraphIndex: this._getAbsParagraphIndexBy(
        positionIndex: this._currentValue?.position.index ?? 0,
        trailingEdge:
        this._currentValue?.position.itemTrailingEdge,
        leadingEdge: this._currentValue?.position.itemLeadingEdge,
      ),
    );

    final position = _itemPositionListener!.itemPositions.value.first;
    int listDataIndex=0;
    if (position.index!=positionTemp) {
      for(int u=0;u<listdatas.length;u++){
        if(cfi==listdatas[u].cfi){
          listDataIndex=u;
          break;
        }
      }
      listdatas[listDataIndex].toJson();
      String str_url_server=uri+'/music';
      var url_server = Uri.parse(str_url_server);
      http.Response response_server = await http.post(
          url_server,
          headers: //<String, String>
          {
            'Content-Type': 'application/json',
          },
          body: json.encode(listdatas[listDataIndex].toJson())
      );
      var responseBody = json.decode(response_server.body);
      Map<String, dynamic> responseMap = responseBody;
      var id=responseMap['Location'];



      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cfi!+id),
        ),
      );
    }
    positionTemp=position.index;
    final chapterIndex = _getChapterIndexBy(
      positionIndex: position.index,
      trailingEdge: position.itemTrailingEdge,
      leadingEdge: position.itemLeadingEdge,
    );
    final paragraphIndex = _getParagraphIndexBy(
      positionIndex: position.index,
      trailingEdge: position.itemTrailingEdge,
      leadingEdge: position.itemLeadingEdge,
    );
    _currentValue = EpubChapterViewValue(
      chapter: chapterIndex >= 0 ? _chapters[chapterIndex] : null,
      chapterNumber: chapterIndex + 1,
      paragraphNumber: paragraphIndex + 1,
      position: position,
    );




    _controller.currentValueListenable.value = _currentValue;
    widget.onChapterChanged?.call(_currentValue);
  }

  void _gotoEpubCfi(
    String? epubCfi, {
    double alignment = 0,
    Duration duration = const Duration(milliseconds: 250),
    Curve curve = Curves.linear,
  }) {
    _epubCfiReader?.epubCfi = epubCfi;
    final index = _epubCfiReader?.paragraphIndexByCfiFragment;

    if (index == null) {
      return;
    }

    _itemScrollController?.scrollTo(
      index: index,
      duration: duration,
      alignment: alignment,
      curve: curve,
    );
  }

  void _onLinkPressed(String href) {
    if (href.contains('://')) {
      widget.onExternalLinkPressed?.call(href);
      return;
    }

    // Chapter01.xhtml#ph1_1 -> [ph1_1, Chapter01.xhtml] || [ph1_1]
    String? hrefIdRef;
    String? hrefFileName;

    if (href.contains('#')) {
      final dividedHref = href.split('#');
      if (dividedHref.length == 1) {
        hrefIdRef = href;
      } else {
        hrefFileName = dividedHref[0];
        hrefIdRef = dividedHref[1];
      }
    } else {
      hrefFileName = href;
    }

    if (hrefIdRef == null) {
      final chapter = _chapterByFileName(hrefFileName);
      if (chapter != null) {
        final cfi = _epubCfiReader?.generateCfiChapter(
          book: _controller._document,
          chapter: chapter,
          additional: ['/4/2'],
        );

        _gotoEpubCfi(cfi);
      }
      return;
    } else {
      final paragraph = _paragraphByIdRef(hrefIdRef);
      final chapter =
          paragraph != null ? _chapters[paragraph.chapterIndex] : null;

      if (chapter != null && paragraph != null) {
        final paragraphIndex =
            _epubCfiReader?.getParagraphIndexByElement(paragraph.element);
        final cfi = _epubCfiReader?.generateCfi(
          book: _controller._document,
          chapter: chapter,
          paragraphIndex: paragraphIndex,
        );

        _gotoEpubCfi(cfi);
      }

      return;
    }
  }

  Paragraph? _paragraphByIdRef(String idRef) =>
      _paragraphs.firstWhereOrNull((paragraph) {
        if (paragraph.element.id == idRef) {
          return true;
        }

        return paragraph.element.children.isNotEmpty &&
            paragraph.element.children[0].id == idRef;
      });

  EpubChapter? _chapterByFileName(String? fileName) =>
      _chapters.firstWhereOrNull((chapter) {
        if (fileName != null) {
          if (chapter.ContentFileName!.contains(fileName)) {
            return true;
          } else {
            return false;
          }
        }
        return false;
      });

  int _getChapterIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    final posIndex = _getAbsParagraphIndexBy(
      positionIndex: positionIndex,
      trailingEdge: trailingEdge,
      leadingEdge: leadingEdge,
    );
    final index = posIndex >= _chapterIndexes.last
        ? _chapterIndexes.length
        : _chapterIndexes.indexWhere((chapterIndex) {
            if (posIndex < chapterIndex) {
              return true;
            }
            return false;
          });

    return index - 1;
  }

  int _getParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    final posIndex = _getAbsParagraphIndexBy(
      positionIndex: positionIndex,
      trailingEdge: trailingEdge,
      leadingEdge: leadingEdge,
    );

    final index = _getChapterIndexBy(positionIndex: posIndex);

    if (index == -1) {
      return posIndex;
    }

    return posIndex - _chapterIndexes[index];
  }

  int _getAbsParagraphIndexBy({
    required int positionIndex,
    double? trailingEdge,
    double? leadingEdge,
  }) {
    int posIndex = positionIndex;
    if (trailingEdge != null &&
        leadingEdge != null &&
        trailingEdge < _minTrailingEdge &&
        leadingEdge < _minLeadingEdge) {
      posIndex += 1;
    }

    return posIndex;
  }

  static Widget _chapterDividerBuilder(EpubChapter chapter) => Container(
        height: 56,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Color(0x24000000),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          chapter.Title ?? '',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

   static Widget _chapterBuilder(
    BuildContext context,
    EpubViewBuilders builders,
    EpubBook document,
    List<EpubChapter> chapters,
    List<Paragraph> paragraphs,
    int index,
    int chapterIndex,
    int paragraphIndex,
    ExternalLinkPressed onExternalLinkPressed,
    int highlightPara,
    void Function(TapDownDetails details)? onTapDown,
    void Function(BuildContext context, int index)? onLongPress,
  ) {
    if (paragraphs.isEmpty) {
      return Container();
    }

    final defaultBuilder = builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return GestureDetector(
      onTapDown: onTapDown,
      onLongPress: () {
        if (onLongPress != null) {
          onLongPress(context,index);
        }
      },
      child: Column(
        children: <Widget>[
          if (chapterIndex >= 0 && paragraphIndex == 0)
            builders.chapterDividerBuilder(chapters[chapterIndex]),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: Container(
                key: ValueKey<String>(index.toString() + (index == highlightPara).toString()),
                color: index == highlightPara ? Colors.blue: Colors.transparent,
                child: Html(
                  data: paragraphs[index].element.outerHtml,
                  onLinkTap: (href, _, __, ___) => onExternalLinkPressed(href!),
                  style: {
                    'html': Style(
                      padding: options.paragraphPadding as EdgeInsets?,
                    ).merge(Style.fromTextStyle(options.textStyle)),
                  },
                  customRender: {
                    'img': (context, buildChildren) {
                      final url = context.tree.element!.attributes['src']!
                          .replaceAll('../', '');
                      return imageMap[url]!;
                    },
                  },
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildLoaded(BuildContext context) {
    return ScrollablePositionedList.builder(
      shrinkWrap: widget.shrinkWrap,
      initialScrollIndex: _epubCfiReader!.paragraphIndexByCfiFragment ?? 0,
      itemCount: _paragraphs.length,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionListener,
      itemBuilder: (BuildContext context, int index) {
        return widget.builders.chapterBuilder(
          context,
          widget.builders,
          widget.controller._document!,
          _chapters,
          _paragraphs,
          index,
          _getChapterIndexBy(positionIndex: index),
          _getParagraphIndexBy(positionIndex: index),
          _onLinkPressed,
          highlightedPara,
          widget.onTapDown,
          widget.onLongPress
        );
      },
    );
  }

  static Widget _builder(
    BuildContext context,
    EpubViewBuilders builders,
    EpubViewLoadingState state,
    WidgetBuilder loadedBuilder,
    Exception? loadingError,
  ) {
    final Widget content = () {
      switch (state) {
        case EpubViewLoadingState.loading:
          return KeyedSubtree(
            key: const Key('epubx.root.loading'),
            child: builders.loaderBuilder?.call(context) ?? const SizedBox(),
          );
        case EpubViewLoadingState.error:
          return KeyedSubtree(
            key: const Key('epubx.root.error'),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: builders.errorBuilder?.call(context, loadingError!) ??
                  Center(child: Text(loadingError.toString())),
            ),
          );
        case EpubViewLoadingState.success:
          return KeyedSubtree(
            key: const Key('epubx.root.success'),
            child: loadedBuilder(context),
          );
      }
    }();

    final defaultBuilder = builders as EpubViewBuilders<DefaultBuilderOptions>;
    final options = defaultBuilder.options;

    return AnimatedSwitcher(
      duration: options.loaderSwitchDuration,
      transitionBuilder: options.transitionBuilder,
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.builders.builder(
      context,
      widget.builders,
      _controller.loadingState.value,
      _buildLoaded,
      _loadingError,
    );
  }

  void highlightPara(int para) {
    setState(() {
      highlightedPara = para;
    });
  }
}

class Data{
  String cfi,emotion,color,weather;

  Data(this.cfi,this.emotion,this.color,this.weather);

  factory Data.fromJson(dynamic json){
    return Data(json['cfi'] as String, json['emotion'] as String,json['color'] as String,json['weather'] as String,);
  }
  Map<String, dynamic> toJson() => {
    'cfi': cfi,
    'emotion': emotion,
    'color' : color,
    'weather' : weather
  };
}
